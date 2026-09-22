#!/usr/bin/with-contenv bash
# shellcheck shell=bash

set -euo pipefail

echo "=== HA Failover Addon ==="
echo "Node role: ${node_role}"
echo "Virtual IP: ${virtual_ip}/${prefix_length}"
echo "Master node IP: ${master_node_ip}"
echo "Backup node IP: ${backup_node_ip}"
echo "Operational mode: ${operational_mode:-vrrp}"

# Funzioni di utilità
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

check_tcp() {
    local host="$1"
    local port="${2:-8123}"
    local timeout="${tcp_timeout:-3}"
    timeout "${timeout}" bash -c "echo > /dev/tcp/${host}/${port}" 2>/dev/null
}

check_ping() {
    local host="$1"
    local count="${2:-1}"
    ping -c "${count}" -W 2 "${host}" >/dev/null 2>&1
}

# === Modalità VRRP (Keepalived) ===
if [[ "${operational_mode:-vrrp}" == "vrrp" ]]; then
    log "Modalità VRRP: avvio Keepalived"

    # Genera keepalived.conf
    cat > /etc/keepalived/keepalived.conf <<EOF
global_defs {
    router_id HA_FAILOVER_$(hostname)
    vrrp_garp_master_delay 5
    vrrp_garp_master_repeat 3
}

vrrp_script check_ha {
    script "/usr/bin/ping -c 1 -W 2 ${master_node_ip}"
    interval 2
    fall 3
    rise 2
}

vrrp_instance VI_1 {
    state ${node_role}
    interface eth0
    virtual_router_id ${vrid}
    priority $([ "${node_role}" = "master" ] && echo "${priority_master}" || echo "${priority_backup}")
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass ${vrrp_password}
    }
    virtual_ipaddress {
        ${virtual_ip}/${prefix_length} dev eth0
    }
    track_script {
        check_ha
    }
}
EOF

    exec /usr/sbin/keepalived -f /etc/keepalived/keepalived.conf --dont-fork

# === Modalità Supervisor (solo Raspberry) ===
elif [[ "${operational_mode}" == "supervisor" ]]; then
    log "Modalità Supervisor: monitoraggio con acquisizione IP tramite API"

    if [[ "${node_role}" != "backup" ]]; then
        log "ERRORE: operational_mode=supervisor richiede node_role=backup"
        exit 1
    fi

    # Variabili di configurazione
    CHECK_INTERVAL="${check_interval:-5}"
    FAILOVER_FAILURES="${failover_failures:-6}"
    FAILOVER_GRACE_PERIOD="${failover_grace_period:-30}"
    FAILBACK_SUCCESSES="${failback_successes:-24}"
    FAILBACK_GRACE_PERIOD="${failback_grace_period:-30}"
    TCP_TIMEOUT="${tcp_timeout:-3}"
    CORE_START_TIMEOUT="${core_start_timeout:-180}"
    CORE_STOP_TIMEOUT="${core_stop_timeout:-60}"
    POST_VIP_ADD_DELAY="${post_vip_add_delay:-5}"
    POST_VIP_REMOVE_DELAY="${post_vip_remove_delay:-5}"

    SUPERVISOR_TOKEN="${SUPERVISOR_TOKEN:-}"
    if [[ -z "${SUPERVISOR_TOKEN}" ]]; then
        log "ERRORE: SUPERVISOR_TOKEN non disponibile. Abilita hassio_api: true nel config.yaml"
        exit 1
    fi

    STATE="STANDBY"
    FAILURE_COUNT=0
    SUCCESS_COUNT=0
    FAILOVER_TIMESTAMP=0

    log "Stato iniziale: ${STATE}"
    log "Master da monitorare: ${master_node_ip}"
    log "Virtual IP da gestire: ${virtual_ip}"

    while true; do
        NOW=$(date +%s)

        # Controlla il master
        MASTER_PING_OK=false
        MASTER_TCP_OK=false

        if check_ping "${master_node_ip}" 1; then
            MASTER_PING_OK=true
        fi

        if check_tcp "${master_node_ip}" 8123 "${TCP_TIMEOUT}"; then
            MASTER_TCP_OK=true
        fi

        MASTER_OK=false
        if [[ "${MASTER_PING_OK}" == "true" && "${MASTER_TCP_OK}" == "true" ]]; then
            MASTER_OK=true
        fi

        log "Stato: ${STATE} | Master ping: ${MASTER_PING_OK} | Master tcp: ${MASTER_TCP_OK} | Failures: ${FAILURE_COUNT} | Successes: ${SUCCESS_COUNT}"

        if [[ "${STATE}" == "STANDBY" ]]; then
            if [[ "${MASTER_OK}" == "false" ]]; then
                FAILURE_COUNT=$((FAILURE_COUNT + 1))
                if [[ ${FAILURE_COUNT} -ge ${FAILOVER_FAILURES} ]]; then
                    log "Soglia failover raggiunta (${FAILOVER_FAILURES} fallimenti). Attendo grace period di ${FAILOVER_GRACE_PERIOD}s..."
                    sleep "${FAILOVER_GRACE_PERIOD}"

                    # Ricontrolla dopo il grace period
                    if ! check_ping "${master_node_ip}" 1 || ! check_tcp "${master_node_ip}" 8123 "${TCP_TIMEOUT}"; then
                        log "Master ancora non raggiungibile. Inizio failover."

                        # Aggiungi VIP tramite Supervisor API
                        log "Aggiunta VIP ${virtual_ip}/${prefix_length}..."
                        # Qui chiameremo l'API /network/interface/<interface>/update
                        # Per ora placeholder
                        # TODO: implementare chiamata API reale

                        sleep "${POST_VIP_ADD_DELAY}"

                        # Avvia Core locale
                        log "Avvio Home Assistant Core locale..."
                        curl -sS --fail \
                            --header "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
                            --header "Content-Type: application/json" \
                            --request POST \
                            --data '{}' \
                            "http://supervisor/core/start" || true

                        # Attendi che il Core risponda
                        CORE_UP=false
                        CORE_START_DEADLINE=$((NOW + CORE_START_TIMEOUT))
                        while [[ $(date +%s) -lt ${CORE_START_DEADLINE} ]]; do
                            if check_tcp "127.0.0.1" 8123 3; then
                                CORE_UP=true
                                break
                            fi
                            sleep 2
                        done

                        if [[ "${CORE_UP}" == "true" ]]; then
                            STATE="FAILOVER_ACTIVE"
                            FAILURE_COUNT=0
                            SUCCESS_COUNT=0
                            FAILOVER_TIMESTAMP=$(date +%s)
                            log "Failover completato. Stato: ${STATE}"
                        else
                            log "ERRORE: Core non riuscito ad avviarsi entro ${CORE_START_TIMEOUT}s"
                        fi
                    else
                        log "Master tornato raggiungibile durante il grace period. Reset conteggio fallimenti."
                        FAILURE_COUNT=0
                    fi
                fi
            else
                FAILURE_COUNT=0
            fi

        elif [[ "${STATE}" == "FAILOVER_ACTIVE" ]]; then
            if [[ "${MASTER_OK}" == "true" ]]; then
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
                if [[ ${SUCCESS_COUNT} -ge ${FAILBACK_SUCCESSES} ]]; then
                    log "Soglia failback raggiunta (${FAILBACK_SUCCESSES} successi). Attendo grace period di ${FAILBACK_GRACE_PERIOD}s..."
                    sleep "${FAILBACK_GRACE_PERIOD}"

                    # Ricontrolla dopo il grace period
                    if check_ping "${master_node_ip}" 1 && check_tcp "${master_node_ip}" 8123 "${TCP_TIMEOUT}"; then
                        log "Master stabile. Inizio failback."

                        # Ferma Core locale
                        log "Arresto Home Assistant Core locale..."
                        curl -sS --fail \
                            --header "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
                            --header "Content-Type: application/json" \
                            --request POST \
                            --data '{"force": false}' \
                            "http://supervisor/core/stop" || true

                        # Attendi che il Core si fermi
                        CORE_STOP_DEADLINE=$((NOW + CORE_STOP_TIMEOUT))
                        while [[ $(date +%s) -lt ${CORE_STOP_DEADLINE} ]]; do
                            if ! check_tcp "127.0.0.1" 8123 3; then
                                break
                            fi
                            sleep 2
                        done

                        # Rimuovi VIP tramite Supervisor API
                        log "Rimozione VIP ${virtual_ip}/${prefix_length}..."
                        # Qui chiameremo l'API /network/interface/<interface>/update
                        # Per ora placeholder
                        # TODO: implementare chiamata API reale

                        sleep "${POST_VIP_REMOVE_DELAY}"

                        STATE="STANDBY"
                        SUCCESS_COUNT=0
                        FAILURE_COUNT=0
                        log "Failback completato. Stato: ${STATE}"
                    else
                        log "Master non più stabile durante il grace period. Reset conteggio successi."
                        SUCCESS_COUNT=0
                    fi
                fi
            else
                SUCCESS_COUNT=0
            fi
        fi

        sleep "${CHECK_INTERVAL}"
    done

else
    log "ERRORE: operational_mode non valido. Usa 'vrrp' o 'supervisor'"
    exit 1
fi

#!/usr/bin/with-contenv bash
set -Eeuo pipefail

CONFIG="/data/options.json"

STATE="STANDBY"
FAILURES=0
SUCCESSES=0

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ha-failover] $*"
}

fail() {
    log "ERRORE: $*"
    exit 1
}

need() {
    command -v "$1" >/dev/null 2>&1 || fail "Comando mancante: $1"
}

opt() {
    jq -r ".$1" "${CONFIG}"
}

is_true() {
    [[ "$1" == "true" ]]
}

vip_present() {
    ip -4 -o addr show dev "${INTERFACE}" \
        | awk '{print $4}' \
        | grep -Fxq "${VIRTUAL_IP}/${PREFIX_LENGTH}"
}

master_ping_ok() {
    ping -n -c 1 -W "${PING_TIMEOUT}" "${MASTER_NODE_IP}" >/dev/null 2>&1
}

master_tcp_ok() {
    nc -z -w "${TCP_TIMEOUT}" "${MASTER_NODE_IP}" 8123 >/dev/null 2>&1
}

master_ok() {
    master_ping_ok && master_tcp_ok
}

supervisor_get() {
    curl -fsS \
        --header "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        "http://supervisor$1"
}

supervisor_post() {
    local endpoint="$1"
    local payload="${2:-{}}"

    curl -fsS -X POST \
        --header "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        --header "Content-Type: application/json" \
        --data "${payload}" \
        "http://supervisor${endpoint}"
}

core_is_running() {
    local response

    response="$(supervisor_get "/core/info" 2>/dev/null || true)"
    [[ -n "${response}" ]] || return 1

    echo "${response}" | jq -e '(.data // .).state == "running"' >/dev/null 2>&1
}

add_vip() {
    if vip_present; then
        log "VIP ${VIRTUAL_IP}/${PREFIX_LENGTH} già presente su ${INTERFACE}."
        return 0
    fi

    log "Aggiungo VIP ${VIRTUAL_IP}/${PREFIX_LENGTH} su ${INTERFACE}."

    ip addr add "${VIRTUAL_IP}/${PREFIX_LENGTH}" dev "${INTERFACE}" || return 1

    if vip_present; then
        log "VIP verificato: presente su ${INTERFACE}."
        return 0
    fi

    log "ERRORE: VIP non trovato dopo l'aggiunta."
    return 1
}

remove_vip() {
    if ! vip_present; then
        log "VIP ${VIRTUAL_IP}/${PREFIX_LENGTH} già assente da ${INTERFACE}."
        return 0
    fi

    log "Rimuovo VIP ${VIRTUAL_IP}/${PREFIX_LENGTH} da ${INTERFACE}."

    ip addr del "${VIRTUAL_IP}/${PREFIX_LENGTH}" dev "${INTERFACE}" || return 1

    if ! vip_present; then
        log "VIP verificato: rimosso da ${INTERFACE}."
        return 0
    fi

    log "ERRORE: VIP ancora presente dopo la rimozione."
    return 1
}

announce_vip() {
    # Il comando è opzionale: accelera l'aggiornamento ARP dei client.
    # La logica di failover resta valida anche se arping non è disponibile.
    if command -v arping >/dev/null 2>&1; then
        local i
        for i in 1 2 3; do
            arping -U -I "${INTERFACE}" -c 1 "${VIRTUAL_IP}" >/dev/null 2>&1 || true
            sleep 1
        done
        log "Annuncio ARP del VIP inviato."
    else
        log "arping non disponibile: proseguo senza gratuitous ARP."
    fi
}

start_core() {
    if core_is_running; then
        log "Home Assistant Core locale già in esecuzione."
        return 0
    fi

    log "Richiedo avvio Home Assistant Core locale."

    supervisor_post "/core/start" "{}" >/dev/null || return 1

    local deadline=$(( $(date +%s) + CORE_START_TIMEOUT ))

    while (( $(date +%s) < deadline )); do
        if core_is_running && nc -z -w 3 127.0.0.1 8123 >/dev/null 2>&1; then
            log "Home Assistant Core locale avviato e raggiungibile."
            return 0
        fi
        sleep 2
    done

    log "ERRORE: timeout avvio Core (${CORE_START_TIMEOUT}s)."
    return 1
}

stop_core() {
    if ! core_is_running; then
        log "Home Assistant Core locale già fermo."
        return 0
    fi

    log "Richiedo arresto Home Assistant Core locale."

    supervisor_post "/core/stop" '{"force":false}' >/dev/null || return 1

    local deadline=$(( $(date +%s) + CORE_STOP_TIMEOUT ))

    while (( $(date +%s) < deadline )); do
        if ! core_is_running; then
            log "Home Assistant Core locale arrestato."
            return 0
        fi
        sleep 2
    done

    log "ERRORE: timeout arresto Core (${CORE_STOP_TIMEOUT}s)."
    return 1
}

failover() {
    log "========== INIZIO FAILOVER =========="

    # Il VIP prima: il Core si avvierà già sull'indirizzo usato dai client.
    if ! add_vip; then
        log "ERRORE: impossibile aggiungere VIP; failover annullato."
        return 1
    fi

    announce_vip
    sleep "${POST_VIP_ADD_DELAY}"

    if ! start_core; then
        log "ERRORE: Core non avviato; rimuovo VIP per non lasciare un endpoint non funzionante."
        remove_vip || true
        return 1
    fi

    STATE="FAILOVER_ACTIVE"
    FAILURES=0
    SUCCESSES=0

    log "========== FAILOVER COMPLETATO =========="
    log "VIP ${VIRTUAL_IP} attivo su ${INTERFACE}; Core backup operativo."
}

failback() {
    log "========== INIZIO FAILBACK =========="
    log "Master ${MASTER_NODE_IP} stabile: arresto Core backup e rilascio VIP."

    # Core prima del VIP: riduce la possibilità che due Core servano automazioni.
    if ! stop_core; then
        log "ERRORE: Core backup non arrestato; non rimuovo il VIP."
        return 1
    fi

    if ! remove_vip; then
        log "ERRORE: VIP non rimosso; Core backup resta fermo per sicurezza."
        return 1
    fi

    sleep "${POST_VIP_REMOVE_DELAY}"

    STATE="STANDBY"
    FAILURES=0
    SUCCESSES=0

    log "========== FAILBACK COMPLETATO =========="
    log "VIP rimosso; Core backup fermo; Raspberry in standby."
}

test_vip() {
    log "========== MODALITÀ TEST VIP =========="
    log "Master e Core non saranno modificati."
    log "Aggiungo ${VIRTUAL_IP}/${PREFIX_LENGTH} per ${VIP_TEST_DURATION}s, poi lo rimuovo."

    add_vip || fail "Test annullato: impossibile aggiungere VIP."
    announce_vip
    sleep "${VIP_TEST_DURATION}"
    remove_vip || fail "Test fallito: impossibile rimuovere VIP."

    log "========== TEST VIP COMPLETATO CON SUCCESSO =========="
}

cleanup() {
    log "Ricevuta richiesta di arresto dell'add-on."

    # Non rimuovere automaticamente il VIP nella modalità operativa:
    # se il Raspberry sta gestendo il failover, toglierlo al riavvio
    # dell'add-on renderebbe Home Assistant irraggiungibile.
    #
    # Il test VIP invece deve sempre pulire l'indirizzo temporaneo.
    if [[ "${TEST_VIP_ONLY:-false}" == "true" ]]; then
        remove_vip || true
    fi
}

need curl
need jq
need ip
need ping
need nc
need awk
need grep

[[ -f "${CONFIG}" ]] || fail "File opzioni non trovato: ${CONFIG}"
[[ -n "${SUPERVISOR_TOKEN:-}" ]] || fail "SUPERVISOR_TOKEN mancante: verifica hassio_api: true."

MASTER_NODE_IP="$(opt master_node_ip)"
VIRTUAL_IP="$(opt virtual_ip)"
PREFIX_LENGTH="$(opt prefix_length)"
INTERFACE="$(opt interface)"

CHECK_INTERVAL="$(opt check_interval)"
PING_TIMEOUT="$(opt ping_timeout)"
TCP_TIMEOUT="$(opt tcp_timeout)"
FAILOVER_FAILURES="$(opt failover_failures)"
FAILOVER_GRACE_PERIOD="$(opt failover_grace_period)"
FAILBACK_SUCCESSES="$(opt failback_successes)"
FAILBACK_GRACE_PERIOD="$(opt failback_grace_period)"
CORE_START_TIMEOUT="$(opt core_start_timeout)"
CORE_STOP_TIMEOUT="$(opt core_stop_timeout)"
POST_VIP_ADD_DELAY="$(opt post_vip_add_delay)"
POST_VIP_REMOVE_DELAY="$(opt post_vip_remove_delay)"
TEST_VIP_ONLY="$(opt test_vip_only)"
VIP_TEST_DURATION="$(opt vip_test_duration)"

ip link show "${INTERFACE}" >/dev/null 2>&1 \
    || fail "Interfaccia non trovata: ${INTERFACE}"

trap cleanup EXIT INT TERM

log "Add-on operativo avviato."
log "Interfaccia backup: ${INTERFACE}"
log "Master monitorato: ${MASTER_NODE_IP}:8123"
log "VIP gestito: ${VIRTUAL_IP}/${PREFIX_LENGTH}"
log "Failover: ${FAILOVER_FAILURES} fallimenti + ${FAILOVER_GRACE_PERIOD}s."
log "Failback: ${FAILBACK_SUCCESSES} successi + ${FAILBACK_GRACE_PERIOD}s."

if is_true "${TEST_VIP_ONLY}"; then
    test_vip
    exit 0
fi

# Se l'add-on viene riavviato durante un failover e trova già il VIP,
# riprende nello stato attivo invece di rimuoverlo.
if vip_present; then
    STATE="FAILOVER_ACTIVE"
    log "VIP già presente all'avvio: riprendo in FAILOVER_ACTIVE."
else
    STATE="STANDBY"
    log "Nessun VIP presente: avvio in STANDBY."
fi

while true; do
    if master_ok; then
        if [[ "${STATE}" == "STANDBY" ]]; then
            FAILURES=0
            SUCCESSES=0
        else
            SUCCESSES=$((SUCCESSES + 1))
            FAILURES=0

            log "Master OK | successi failback=${SUCCESSES}/${FAILBACK_SUCCESSES}."

            if (( SUCCESSES >= FAILBACK_SUCCESSES )); then
                log "Soglia failback raggiunta; attendo grace period ${FAILBACK_GRACE_PERIOD}s."
                sleep "${FAILBACK_GRACE_PERIOD}"

                if master_ok; then
                    failback || true
                else
                    log "Master non più disponibile dopo grace period; failback annullato."
                    SUCCESSES=0
                fi
            fi
        fi
    else
        if [[ "${STATE}" == "FAILOVER_ACTIVE" ]]; then
            SUCCESSES=0
            FAILURES=0
            log "Master KO; mantengo VIP e Core backup attivi."
        else
            FAILURES=$((FAILURES + 1))
            SUCCESSES=0

            log "Master KO | fallimenti failover=${FAILURES}/${FAILOVER_FAILURES}."

            if (( FAILURES >= FAILOVER_FAILURES )); then
                log "Soglia failover raggiunta; attendo grace period ${FAILOVER_GRACE_PERIOD}s."
                sleep "${FAILOVER_GRACE_PERIOD}"

                if ! master_ok; then
                    failover || true
                else
                    log "Master recuperato durante grace period; failover annullato."
                    FAILURES=0
                fi
            fi
        fi
    fi

    sleep "${CHECK_INTERVAL}"
done

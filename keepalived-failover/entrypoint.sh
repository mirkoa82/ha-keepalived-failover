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
            log "

#!/usr/bin/with-contenv bash
set -Eeuo pipefail

CONFIG="/data/options.json"

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

master_ok() {
    ping -n -c 1 -W "${PING_TIMEOUT}" "${MASTER_NODE_IP}" >/dev/null 2>&1 \
        && nc -z -w "${TCP_TIMEOUT}" "${MASTER_NODE_IP}" 8123 >/dev/null 2>&1
}

need curl
need jq
need ip
need ping
need nc

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
FAILBACK_SUCCESSES="$(opt failback_successes)"

ip link show "${INTERFACE}" >/dev/null 2>&1 \
  || fail "Interfaccia non trovata: ${INTERFACE}"

log "Avvio in modalità diagnostica: non verranno modificati VIP o Core."
log "Interfaccia: ${INTERFACE}"
log "Master: ${MASTER_NODE_IP}:8123"
log "VIP pianificato: ${VIRTUAL_IP}/${PREFIX_LENGTH}"
log "Soglia failover: ${FAILOVER_FAILURES} fallimenti."
log "Soglia failback: ${FAILBACK_SUCCESSES} successi."

INFO="$(curl -fsS \
  --header "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
  http://supervisor/info 2>&1 || true)"

if [[ -n "${INFO}" ]]; then
    log "Supervisor API raggiungibile."
    echo "${INFO}" | jq -c '.' || true
else
    log "ATTENZIONE: Supervisor API non raggiungibile con /info."
fi

FAILURES=0
SUCCESSES=0

while true; do
    if master_ok; then
        SUCCESSES=$((SUCCESSES + 1))
        FAILURES=0
        log "Master OK | successi=${SUCCESSES}/${FAILBACK_SUCCESSES}, fallimenti=0"
    else
        FAILURES=$((FAILURES + 1))
        SUCCESSES=0
        log "Master KO | fallimenti=${FAILURES}/${FAILOVER_FAILURES}, successi=0"
    fi

    sleep "${CHECK_INTERVAL}"
done

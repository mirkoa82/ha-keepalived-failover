#!/usr/bin/with-contenv bashio
set -euo pipefail

NODE_ROLE="$(bashio::config 'node_role')"
MASTER_NODE_IP="$(bashio::config 'master_node_ip')"
BACKUP_NODE_IP="$(bashio::config 'backup_node_ip')"

case "${NODE_ROLE}" in
    master)
        EXPECTED_NODE_IP="${MASTER_NODE_IP}"
        ;;
    backup)
        EXPECTED_NODE_IP="${BACKUP_NODE_IP}"
        ;;
    *)
        bashio::log.fatal "node_role non valido: ${NODE_ROLE}"
        exit 1
        ;;
esac

bashio::log.info "Ruolo configurato: ${NODE_ROLE}"
bashio::log.info "Ricerca dell'interfaccia che possiede ${EXPECTED_NODE_IP}..."

if DETECTED="$(
    /usr/local/bin/detect_interface.sh "${EXPECTED_NODE_IP}"
)"; then
    INTERFACE="${DETECTED%%|*}"
    LOCAL_ADDRESS="${DETECTED#*|}"

    bashio::log.info "Interfaccia rilevata automaticamente: ${INTERFACE}"
    bashio::log.info "Indirizzo locale rilevato: ${LOCAL_ADDRESS}"
else
    bashio::log.fatal "Impossibile rilevare univocamente l'interfaccia per ${EXPECTED_NODE_IP}."
    exit 1
fi

CAP_EFF_HEX="$(awk '/CapEff/ { print $2 }' /proc/self/status)"
CAP_EFF_DEC=$((16#${CAP_EFF_HEX}))

bashio::log.info "Capability effettive del container (CapEff): ${CAP_EFF_HEX}"

if (( (CAP_EFF_DEC & (1 << 12)) != 0 )); then
    bashio::log.info "CAP_NET_ADMIN presente."
else
    bashio::log.warning "CAP_NET_ADMIN NON presente."
fi

if (( (CAP_EFF_DEC & (1 << 13)) != 0 )); then
    bashio::log.info "CAP_NET_RAW presente."
else
    bashio::log.warning "CAP_NET_RAW NON presente."
fi

bashio::log.info "Test completato: nessuna modifica di rete applicata."

while true; do
    sleep 3600
done

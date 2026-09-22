#!/usr/bin/with-contenv bashio
set -e

bashio::log.info "Keepalived HA Failover avviato correttamente."
bashio::log.info "Test rete: elenco interfacce disponibili."

ip -brief link || true
ip -brief address || true

bashio::log.info "Test rete completato: nessuna modifica applicata."

while true; do
    sleep 3600
done

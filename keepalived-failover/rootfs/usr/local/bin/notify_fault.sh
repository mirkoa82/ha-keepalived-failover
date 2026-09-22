#!/bin/bash

source /usr/local/share/ha-failover/env 2>/dev/null || true
LOG_FILE="/var/log/ha-failover.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> $LOG_FILE
}

log "⚠️ === STATO FAULT ==="
log "Problema critico con keepalived su questo nodo"

# Qui potresti inviare un alert urgente
# curl -X POST "https://api.telegram.org/botTOKEN/sendMessage" \
#   -d chat_id=YOUR_ID \
#   -d text="⚠️ HA Failover: STATO FAULT su questo nodo"

echo "fault" > /usr/local/share/ha-failover/state

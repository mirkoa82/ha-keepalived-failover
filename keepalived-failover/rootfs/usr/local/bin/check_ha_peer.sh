#!/bin/bash

# Carica variabili ambiente
source /usr/local/share/ha-failover/env 2>/dev/null || true

LOG_FILE="/var/log/keepalived-check.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> $LOG_FILE
}

# Determina quale IP controllare in base al ruolo corrente
CURRENT_STATE=$(cat /usr/local/share/ha-failover/state 2>/dev/null || echo "unknown")

if [ "$NODE_ROLE" = "master" ]; then
    # Questo è il master, controlla se lo slave è vivo (opzionale)
    PEER_IP="$SLAVE_NODE_IP"
    log "Master: controllo peer (slave) $PEER_IP"
    exit 0  # Il master rimane sempre master se HA è attivo
else
    # Questo è il backup, controlla se il master è vivo
    PEER_IP="$MASTER_NODE_IP"
    log "Backup: controllo master $PEER_IP:$HA_PORT"
fi

# Controllo 1: Ping
if ! ping -c 2 -W 3 $PEER_IP > /dev/null 2>&1; then
    log "❌ Ping fallito verso $PEER_IP"
    exit 1
fi

# Controllo 2: Porta HTTP di Home Assistant
if ! timeout 3 bash -c "echo > /dev/tcp/$PEER_IP/$HA_PORT" 2>/dev/null; then
    log "❌ Porta $HA_PORT chiusa su $PEER_IP"
    exit 1
fi

# Controllo 3: API di Home Assistant (opzionale, più robusto)
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://$PEER_IP:$HA_PORT/api" 2>/dev/null)

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ]; then
    log "✅ HA peer ($PEER_IP) è VIVO (HTTP $HTTP_CODE)"
    exit 0
else
    log "⚠️ HA peer ($PEER_IP) risponde HTTP $HTTP_CODE"
    exit 1
fi

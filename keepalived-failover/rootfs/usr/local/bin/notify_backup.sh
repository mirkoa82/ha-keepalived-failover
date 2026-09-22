#!/bin/bash

source /usr/local/share/ha-failover/env 2>/dev/null || true
LOG_FILE="/var/log/ha-failover.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> $LOG_FILE
}

log "🔴 === TORNATO BACKUP ==="
log "VIP: $VIRTUAL_IP su $INTERFACE"

# 1. Ferma Home Assistant
log "🛑 Fermo Home Assistant..."

if command -v ha &> /dev/null; then
    ha core stop && log "✅ HA fermato tramite 'ha core stop'"
elif docker ps --format '{{.Names}}' | grep -q "homeassistant"; then
    docker stop homeassistant && log "✅ HA fermato tramite Docker"
elif systemctl is-active --quiet home-assistant@homeassistant.service 2>/dev/null; then
    systemctl stop home-assistant@homeassistant.service && log "✅ HA fermato tramite systemd"
else
    log "⚠️ Nessun metodo di stop HA trovato"
fi

# 2. Rimuovi il VIP
ip addr del $VIRTUAL_IP/24 dev $INTERFACE 2>/dev/null
log "❌ VIP $VIRTUAL_IP rimosso"

# 3. Aggiorna stato
echo "backup" > /usr/local/share/ha-failover/state

log "✅ Failback completato - HA master originale presumibilmente attivo"

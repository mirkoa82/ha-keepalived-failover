#!/bin/bash

source /usr/local/share/ha-failover/env 2>/dev/null || true
LOG_FILE="/var/log/ha-failover.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> $LOG_FILE
}

log "🟢 === DIVENTATO MASTER ==="
log "VIP: $VIRTUAL_IP su $INTERFACE"

# 1. Aggiungi il VIP (keepalived lo fa già, ma esplicitiamo)
ip addr add $VIRTUAL_IP/24 dev $INTERFACE 2>/dev/null
log "✅ VIP $VIRTUAL_IP aggiunto"

# 2. Gratuitous ARP per aggiornare le tabelle ARP
arping -U -I $INTERFACE -c 3 $VIRTUAL_IP 2>/dev/null
log "📡 Gratuitous ARP inviato"

# 3. Avvia Home Assistant
log "🚀 Avvio Home Assistant..."

# Prova diversi metodi
if command -v ha &> /dev/null; then
    ha core start && log "✅ HA avviato tramite 'ha core start'"
elif docker ps --format '{{.Names}}' | grep -q "homeassistant"; then
    docker start homeassistant && log "✅ HA avviato tramite Docker"
elif systemctl is-active --quiet home-assistant@homeassistant.service 2>/dev/null; then
    systemctl start home-assistant@homeassistant.service && log "✅ HA avviato tramite systemd"
else
    log "⚠️ Nessun metodo di avvio HA trovato"
fi

# 4. Aggiorna stato
echo "master" > /usr/local/share/ha-failover/state

# 5. Notifica opzionale (es. Telegram, email, webhook)
# curl -X POST "https://api.telegram.org/botTOKEN/sendMessage" \
#   -d chat_id=YOUR_ID \
#   -d text="🔄 HA Failover: questo nodo è diventato MASTER ($VIRTUAL_IP)"

log "✅ Failover completato - HA attivo su $VIRTUAL_IP"

#!/bin/bash
set -e

echo "🔧 Generazione configurazione Keepalived..."

# Determina il ruolo del nodo
if [ "$NODE_ROLE" = "auto" ]; then
    # Auto-detect: se questo nodo è master_node_ip, usa priorità alta
    CURRENT_IP=$(hostname -i 2>/dev/null || ip -4 addr show $INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    
    if [ "$CURRENT_IP" = "$MASTER_NODE_IP" ]; then
        NODE_ROLE="master"
        echo "✅ Rilevato come nodo MASTER (IP: $MASTER_NODE_IP)"
    else
        NODE_ROLE="backup"
        echo "✅ Rilevato come nodo BACKUP (IP: $SLAVE_NODE_IP)"
    fi
fi

# Imposta stato e priorità in base al ruolo
if [ "$NODE_ROLE" = "master" ]; then
    STATE="MASTER"
    PRIORITY=$PRIORITY_MASTER
    PREEMPT="preempt_delay 0"
    NODE_ID="MASTER"
else
    STATE="BACKUP"
    PRIORITY=$PRIORITY_BACKUP
    PREEMPT=""
    NODE_ID="BACKUP"
fi

# Esporta variabili per il template
export STATE PRIORITY PREEMPT NODE_ID

# Genera keepalived.conf dal template
envsubst '${STATE} ${PRIORITY} ${PREEMPT} ${NODE_ID} ${INTERFACE} ${VRID} ${ADVERT_INTERVAL} ${PASSWORD} ${VIRTUAL_IP} ${CHECK_INTERVAL}' \
    < /etc/keepalived/keepalived.conf.template \
    > /etc/keepalived/keepalived.conf

echo "📄 Configurazione generata:"
cat /etc/keepalived/keepalived.conf

# Esporta variabili per gli script di notifica
mkdir -p /usr/local/share/ha-failover
echo "export VIRTUAL_IP=\"$VIRTUAL_IP\"" > /usr/local/share/ha-failover/env
echo "export MASTER_NODE_IP=\"$MASTER_NODE_IP\"" >> /usr/local/share/ha-failover/env
echo "export SLAVE_NODE_IP=\"$SLAVE_NODE_IP\"" >> /usr/local/share/ha-failover/env
echo "export HA_PORT=\"$HA_PORT\"" >> /usr/local/share/ha-failover/env
echo "export NODE_ROLE=\"$NODE_ROLE\"" >> /usr/local/share/ha-failover/env
echo "export INTERFACE=\"$INTERFACE\"" >> /usr/local/share/ha-failover/env

echo "✅ Configurazione completata. Avvio keepalived..."

# Avvia keepalived
exec "$@"

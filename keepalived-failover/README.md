# Keepalived HA Failover per Home Assistant

Add-on per gestire automaticamente il failover di un IP virtuale (VIP) tra due nodi Home Assistant usando VRRP.

## Caratteristiche

- ✅ Failover automatico quando il nodo master fallisce
- ✅ Failback automatico quando il master torna online
- ✅ Gestione start/stop di Home Assistant
- ✅ Configurazione semplice via UI
- ✅ Supporto per auto-detect del ruolo

## Installazione

### 1. Aggiungi il repository

In Home Assistant:
1. Vai su **Impostazioni** → **Componenti aggiuntivi**
2. Clicca sui **tre puntini** in alto a destra → **Repository**
3. Incolla: `https://github.com/tuo-username/ha-keepalived-failover`
4. Clicca **Aggiungi**

### 2. Installa l'add-on

1. Cerca "Keepalived HA Failover" nello store
2. Clicca **Installa**
3. **Installa su entrambi i nodi** (master e backup)

### 3. Configura

#### Nodo Master (es. 10.14.0.237):

```yaml
node_role: "master"
virtual_ip: "10.14.0.250"
master_node_ip: "10.14.0.237"
slave_node_ip: "10.14.0.245"
```

#### Nodo Backup (es. 10.14.0.245):

```yaml
node_role: "backup"
virtual_ip: "10.14.0.250"
master_node_ip: "10.14.0.237"
slave_node_ip: "10.14.0.245"
```

### 4. Avvia

1. Clicca **Avvia** su entrambi i nodi
2. Attendi che si stabilizzino (15-30 secondi)
3. Verifica i log

## Configurazione completa

| Parametro | Descrizione | Default |
|-----------|-------------|---------|
| `node_role` | Ruolo: "master", "backup", o "auto" | "auto" |
| `virtual_ip` | IP virtuale (VIP) da usare per il failover | "10.14.0.250" |
| `master_node_ip` | IP fisico del nodo master | "10.14.0.237" |
| `slave_node_ip` | IP fisico del nodo backup | "10.14.0.245" |
| `vrid` | Virtual Router ID (deve essere uguale su entrambi) | 51 |
| `password` | Password VRRP (deve essere uguale su entrambi) | "haus3r2026" |
| `priority_master` | Priorità del nodo master | 150 |
| `priority_backup` | Priorità del nodo backup | 90 |
| `advert_interval` | Intervallo advertisement VRRP (secondi) | 1 |
| `check_interval` | Intervallo controllo health (secondi) | 5 |
| `ha_port` | Porta di Home Assistant | 8123 |
| `interface` | Interfaccia di rete | "eth0" |
| `enable_preempt` | Se true, il master riprende il VIP quando torna | true |

## Funzionamento

1. **Stato normale**: Il master detiene il VIP e HA è attivo
2. **Failover**: Se il master fallisce, il backup acquisisce il VIP e avvia HA
3. **Failback**: Quando il master torna, il backup rilascia il VIP e ferma HA

## Log

- **Log add-on**: Pannello add-on → Log
- **Log keepalived**: `docker logs hassio_addon_keepalived_failover`
- **Log failover**: `/var/log/ha-failover.log` (dentro il container)

## Verifica

```bash
# Controlla se il VIP è attivo
ip addr show eth0 | grep 10.14.0.250

# Test failover: ferma l'add-on sul master
# Il backup dovrebbe acquisire il VIP dopo 15-20 secondi
```

## Problemi noti

### "Operation not permitted"

Se vedi errori RTNETLINK, HassOS potrebbe bloccare NET_ADMIN. In tal caso:
- Usa Home Assistant Container invece di HassOS
- Oppure usa una VM Linux separata per keepalived

## Supporto

Segnala problemi su: https://github.com/tuo-username/ha-keepalived-failover/issues

ARG BUILD_FROM
FROM $BUILD_FROM

# Installa dipendenze
RUN apk add --no-cache \
    keepalived \
    iproute2 \
    arping \
    curl \
    jq \
    bash \
    python3 \
    py3-requests

# Crea directory per script e stato
RUN mkdir -p /etc/keepalived /var/run/keepalived /usr/local/share/ha-failover

# Copia file di configurazione e script
COPY rootfs / 

# Imposta permessi
RUN chmod +x \
    /etc/cont-init.d/01-generate-config.sh \
    /usr/local/bin/check_ha_peer.sh \
    /usr/local/bin/notify_master.sh \
    /usr/local/bin/notify_backup.sh \
    /usr/local/bin/notify_fault.sh

# Inizializza file di stato
RUN echo "unknown" > /usr/local/share/ha-failover/state

EXPOSE 50

ENTRYPOINT ["/etc/cont-init.d/01-generate-config.sh"]
CMD ["keepalived", "--dont-fork", "--log-console", "--release-vips"]

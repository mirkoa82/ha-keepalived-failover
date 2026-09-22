ARG BUILD_FROM
FROM $BUILD_FROM

RUN apk add --no-cache \
    bash \
    curl \
    iproute2 \
    keepalived \
    arping \
    gettext

COPY rootfs /

RUN chmod +x \
    /etc/cont-init.d/01-generate-config.sh \
    /run.sh \
    /usr/local/bin/generate_keepalived_config.sh \
    /usr/local/bin/check_local_ha.sh \
    /usr/local/bin/ha_core_control.sh \
    /usr/local/bin/notify_master.sh \
    /usr/local/bin/notify_backup.sh \
    /usr/local/bin/notify_fault.sh

CMD ["/run.sh"]

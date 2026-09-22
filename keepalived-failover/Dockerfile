ARG BUILD_FROM
FROM $BUILD_FROM

RUN apk add --no-cache \
    bash \
    curl \
    iproute2 \
    keepalived \
    arping

COPY rootfs /

RUN chmod 755 \
    /run.sh \
    /usr/local/bin/detect_interface.sh

CMD ["/run.sh"]

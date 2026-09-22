ARG BUILD_FROM
FROM $BUILD_FROM

RUN apk add --no-cache \
    bash \
    curl \
    iproute2 \
    keepalived \
    arping

COPY rootfs /

RUN chmod +x /run.sh

CMD ["/run.sh"]

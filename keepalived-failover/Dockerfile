ARG BUILD_FROM
FROM $BUILD_FROM

RUN apk add --no-cache \
    bash \
    curl \
    jq \
    iproute2 \
    iputils \
    busybox-extras

COPY entrypoint.sh /entrypoint.sh
RUN chmod a+x /entrypoint.sh

CMD ["/entrypoint.sh"]

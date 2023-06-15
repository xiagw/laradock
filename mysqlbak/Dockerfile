FROM databack/mysql-backup
ARG CHANGE_SOURCE=false
ARG TZ=UTC
ENV TZ ${TZ}

RUN set -xe; \
    if [ "${CHANGE_SOURCE}" = true ] || [ "${IN_CHINA}" = true ]; then \
    sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/' /etc/apk/repositories; \
    fi; \
    apk update; \
    apk add --no-cache --update dumb-init

ENTRYPOINT [ "/usr/bin/dumb-init", "--" ]
CMD ["/entrypoint"]
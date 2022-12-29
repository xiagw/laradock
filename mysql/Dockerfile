ARG MYSQL_VERSION
FROM mysql:${MYSQL_VERSION}

LABEL maintainer="Mahmoud Zalt <mahmoud@zalt.me>"

#####################################
# Set Timezone
#####################################

ARG TZ=UTC
ENV TZ ${TZ}
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && chown -R mysql:root /var/lib/mysql/

COPY my.cnf /etc/mysql/conf.d/my.cnf
COPY backup.sh /opt/

ARG MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
ARG MYSQL_SLAVE=false
RUN chmod 0444 /etc/mysql/conf.d/my.cnf \
    && chmod +x /opt/backup.sh \
    && printf "[client]\npassword=%s\n" "${MYSQL_ROOT_PASSWORD}" >/root/.my.cnf \
    && printf "export LANG=C.UTF-8" >/root/.bashrc \
    && if [ "$MYSQL_SLAVE" = 'true' ]; then sed -i -e "/server_id/s/1/${MYSQL_SLAVE_ID:-2}/" -e "/auto_increment_offset/s/1/2/" /etc/mysql/conf.d/my.cnf; fi

CMD ["mysqld"]

EXPOSE 3306

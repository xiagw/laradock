ARG MYSQL_VERSION
FROM mysql:${MYSQL_VERSION}

#####################################
# Set Timezone
#####################################
ARG TZ=UTC
ENV TZ ${TZ}

ARG MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
ARG MYSQL_SLAVE=false

RUN if [ ${MYSQL_VERSION} > '8.4.0-0.000' ]; then \
  echo 'mysql_native_password=on' >> /etc/mysql/conf.d/my.cnf \
else \
  echo 'default-authentication-plugin=mysql_native_password' >> /etc/mysql/conf.d/my.cnf \
;fi

EXPOSE 3306

COPY ./root/ /

RUN bash /opt/build.sh

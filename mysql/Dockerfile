ARG MYSQL_VERSION=8.0
FROM mysql:${MYSQL_VERSION}

#####################################
# Set Timezone
#####################################
ARG TZ=UTC
ENV TZ ${TZ}

ARG MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}

ARG MYSQL_REPLICATION=single
# ARG MYSQL_REPLICATION=master1
# ARG MYSQL_REPLICATION=master2

EXPOSE 3306

COPY ./root/ /

RUN bash /opt/build.sh

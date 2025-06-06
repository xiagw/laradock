ARG MYSQL_VERSION=8.0
FROM mysql:${MYSQL_VERSION}

#####################################
# Set Timezone
#####################################
ARG TZ=UTC
ENV TZ=${TZ}

ARG MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}

# Replication configuration
## MYSQL_REPL_TYPE=single: Single instance
## MYSQL_REPL_TYPE=master2slave: Master to Slave
## MYSQL_REPL_TYPE=master2master: Master to Master
ARG MYSQL_REPL_TYPE=single
ARG MYSQL_ROLE=slave
ARG MYSQL_MASTER_HOST=mysql1
ARG MYSQL_REPL_USER=repl
ARG MYSQL_REPL_PASSWORD=replpass

ENV MYSQL_REPL_TYPE=${MYSQL_REPL_TYPE}
ENV MYSQL_ROLE=${MYSQL_ROLE}
ENV MYSQL_MASTER_HOST=${MYSQL_MASTER_HOST}
ENV MYSQL_REPL_USER=${MYSQL_REPL_USER}
ENV MYSQL_REPL_PASSWORD=${MYSQL_REPL_PASSWORD}

EXPOSE 3306

COPY ./root/ /

RUN bash /opt/build.sh

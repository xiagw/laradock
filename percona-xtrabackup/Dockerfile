# ARG PXB_VERSION=2.4
ARG PXB_VERSION=8.1
FROM percona/percona-xtrabackup:${PXB_VERSION}
# USER root
# RUN groupmod -g 999 mysql && usermod -u 999 -g 999 mysql
COPY ./root/ /
CMD ["bash", "/opt/run.sh"]
# USER mysql
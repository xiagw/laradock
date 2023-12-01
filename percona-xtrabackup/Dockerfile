FROM percona/percona-xtrabackup:8.1
USER root
RUN groupmod -g 999 mysql && usermod -u 999 -g 999 mysql
# COPY ./root/ /
# CMD ["/opt/run.sh"]
USER mysql
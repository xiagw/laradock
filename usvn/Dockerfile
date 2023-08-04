FROM php:7.4-apache
## for apt to be noninteractive
ENV DEBIAN_FRONTEND noninteractive
ENV DEBCONF_NONINTERACTIVE_SEEN true
ENV TIME_ZOME Asia/Shanghai

COPY ./root/opt/build.sh /opt/
RUN bash /opt/build.sh

COPY ./root/ /
RUN [ -f /opt/run.sh ] && chmod +x /opt/run.sh
CMD ["/opt/run.sh"]

## On Host:
## echo 'fs.inotify.max_user_watches = 99999999' | sudo tee -a /etc/sysctl.d/99-sysctl.conf
## sudo sysctl -p
## cat /proc/sys/fs/inotify/max_user_watches


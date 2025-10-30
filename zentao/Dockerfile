
# ARG ZT_VERSION=latest
ARG ZT_VERSION=21.7.6
FROM hub.zentao.net/app/zentao:${ZT_VERSION}
LABEL maintainer="xiagw <fxiaxiaoyu@gmail.com>"

ENV ZT_VERSION=${ZT_VERSION}
ENV ZT_MYSQL_HOST=rm-xxxxxxxxxx.rwlb.rds.aliyuncs.com
ENV ZT_MYSQL_PORT=3306
ENV ZT_MYSQL_USER=zentao
ENV ZT_MYSQL_PASSWORD=zentao
ENV ZT_MYSQL_DB=zentao
ENV APP_DOMAIN=zen.example.com
ENV PHP_MAX_EXECUTION_TIME=120
ENV PHP_MEMORY_LIMIT=512M
ENV PHP_POST_MAX_SIZE=1024M
ENV PHP_UPLOAD_MAX_FILESIZE=1024M
ENV LDAP_ENABLED=false
ENV SMTP_ENABLED=false
ENV APP_DEFAULT_PORT=80
ENV PROTOCOL_TYPE=http
ENV IS_CONTAINER=true
ENV LINK_GIT=false
ENV LINK_CI=false

COPY root/ /
RUN sed -i "/template.*estimate/s/=.*/= '8';/" /apps/zentao/module/task/config.php



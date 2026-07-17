ARG MIRROR=
ARG NODE_VERSION=20
FROM ${MIRROR}node:${NODE_VERSION}-slim

ARG CHANGE_SOURCE=false
ARG IN_CHINA=false

EXPOSE 8080
WORKDIR /app
CMD [ "bash", "/app/run.sh" ]
# CMD [ "npm", "run", "start" ]

# COPY ./root/ /
# SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN set -xe; \
  [ -d /.cache ] || mkdir /.cache; \
  [ -d /app ] || mkdir /app; \
  chown -R node:node /.cache /app; \
  if [ "$CHANGE_SOURCE" = true ]; then \
    sed -i 's/deb.debian.org/mirrors.ustc.edu.cn/g' /etc/apt/sources.list.d/debian.sources; \
    apt update; \
    apt install -y curl; \
    npm config set registry https://registry.npmmirror.com/; \
    yarn config set registry https://registry.npmmirror.com/; \
    npm install -g cnpm; \
  fi; \
  npm install -g npm

USER node

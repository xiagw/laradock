## nodejs template
ARG NODE_VERSION=18
FROM node:${NODE_VERSION}-slim

ARG CHANGE_SOURCE=false

EXPOSE 8080
WORKDIR /app
CMD [ "bash", "-c", "/app/run.sh" ]
# CMD [ "npm", "run", "start" ]

# COPY ./root/ /
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN set -xe; \
  [ -d /.cache ] || mkdir /.cache; \
  [ -d /app ] || mkdir /app; \
  chown -R node:node /.cache /app; \
  npm config set registry https://registry.npmmirror.com/; \
  if [ "$CHANGE_SOURCE" = true ]; then \
    npm install -g cnpm; \
  fi
  # yarn config set registry https://registry.npmmirror.com/; \
  # npm install -g npm; \

USER node
COPY --chown=node:node ./package.json .
RUN set -xe; \
  if [ "$CHANGE_SOURCE" = true ]; then \
    cnpm install; \
  else \
    npm install; \
  fi

ONBUILD COPY --chown=node:node . .
ONBUILD RUN set -xe; if [ -f /opt/onbuild.sh ]; then bash /opt/onbuild.sh; else :; fi

# podman build --force-rm --format=docker -t deploy/base:node-v18t01 -f Dockerfile.base .
# docker build --force-rm -t deploy/base:node-v18t01 -f Dockerfile.base .

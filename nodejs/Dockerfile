## nodejs template
ARG NODE_VERSION=18
FROM node:${NODE_VERSION}-slim

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
    npm config set registry https://registry.npmmirror.com/; \
    yarn config set registry https://registry.npmmirror.com/; \
    npm install -g cnpm; \
  fi; \
  npm install -g npm

USER node

# https://developers.tron.network/docs/fullnode
FROM openjdk:8

WORKDIR /project/tron/

# cd /project/tron/
RUN git clone -b master https://github.com/tronprotocol/java-tron.git \
    &&cd ./java-tron && ./gradlew build
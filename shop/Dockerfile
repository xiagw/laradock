FROM gradle:5.5.1-jdk8 as BUILDER
# FROM openjdk:8 as BUILDER
# ARG GIT_BRANCH=testing
ARG USE_PROXY=false
ARG PROXY_HOST=192.168.64.150
ARG PROXY_PORT=10800

WORKDIR /home/gradle/project

COPY . .
# COPY ./gradle-5.5.1-bin.zip /home/gradle/.gradle/wrapper/dists/gradle-5.5.1-bin/cfsov38hb3r1zj4ic9bbjcc7n/
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN set -xe \
    && chmod +x gradlew \
    && if [ ${USE_PROXY} = true ]; then \
    ./gradlew -Dhttp.proxyHost=$PROXY_HOST -Dhttp.proxyPort=$PROXY_PORT -Dhttps.proxyHost=$PROXY_HOST -Dhttps.proxyPort=$PROXY_PORT clean; \
    ./gradlew -Dhttp.proxyHost=$PROXY_HOST -Dhttp.proxyPort=$PROXY_PORT -Dhttps.proxyHost=$PROXY_HOST -Dhttps.proxyPort=$PROXY_PORT war; \
    else \
    ./gradlew clean; \
    ./gradlew war; \
    fi \
    && find . -name '*.war' -print0 | xargs -0 -I {} cp {} ROOT.war

##################################
FROM tomcat:8 as tomcat

COPY --from=BUILDER /home/gradle/project/ROOT.war /usr/local/tomcat/

RUN set -xe \
    && sed -i -e '/Connector port="8080"/ a URIEncoding="UTF-8"' /usr/local/tomcat/conf/server.xml \
    # -e '/appBase="webapps"/ a reloadable="false"' /usr/local/tomcat/conf/server.xml \
    && sed -i -e '/OS\ specific/ a JAVA_OPTS="-server -Xms256m -Xmx512m"' /usr/local/tomcat/bin/catalina.sh \
    && useradd -m -s /bin/bash -u 1000 tomcat \
    && chown -R 1000:1000 /usr/local/tomcat

# USER 1000
USER tomcat

EXPOSE 8080


ARG SPRING_JDK_VERSION=17
FROM amazoncorretto:${SPRING_JDK_VERSION}

WORKDIR /app

COPY entrypoint.sh /usr/local/bin/spring-entrypoint.sh
RUN chmod +x /usr/local/bin/spring-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/spring-entrypoint.sh"]
CMD ["tail", "-f", "/dev/null"]

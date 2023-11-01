## spring
location /spring {
    proxy_pass http://127.0.0.1:8080;
    # proxy_pass http://spring:8080;
}
location /spring-ui {
    proxy_pass http://127.0.0.1:8081;
    # proxy_pass http://spring:8081;
}
## spring2
location /spring2 {
    proxy_pass http://127.0.0.1:8080;
    # proxy_pass http://spring2:8080;
}
location /spring2-ui {
    proxy_pass http://127.0.0.1:8081;
    # proxy_pass http://spring2:8081;
}

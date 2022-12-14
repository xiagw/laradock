## !!! change me !!!
location /spring {
    proxy_pass http://spring:8080;
}
location /spring-ui {
    proxy_pass http://spring:8081;
}
# location /spring1 {
#     proxy_pass http://spring1:8080;
# }
# location /spring1-ui {
#     proxy_pass http://spring1:8081;
# }

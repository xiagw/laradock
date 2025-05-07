## 1. location /xxx 自行定义URI xxx, 例如: http://example.com/xxx/
## 2. proxy_pass 后面必须对应 docker 容器名字，当前一般是 spring 和 nodejs
## 3. 注意移除注释 #

## 禁止访问的URI
# location /xxxxx {
#     return 404;
# }

## node.js
location /nodejs {
    # proxy_pass http://nodejs:8080;
}

## spring
location /spring {
    # proxy_pass http://spring:8080;
}
location /spring-ui {
    # proxy_pass http://spring:8081;
}
## spring2
location /spring2 {
    # proxy_pass http://spring2:8080;
}
location /spring2-ui {
    # proxy_pass http://spring2:8081;
}

location /go-uri/ {
    # proxy_pass http://golang:5000;
}

## 1. location /xxx 自行定义URI xxx, 例如: http://example.com/xxx/
## 2. proxy_pass 后面必须对应 docker 容器名字，当前一般是 spring 和 nodejs
## 3. 注意移除注释 #
## 4. 多实例（spring-17a 等）配置由 ./fly.sh add / nginx-gen 自动生成独立的 <name>.inc，
##    本文件只放单实例 spring/nodejs 与负载均衡/自定义规则

## 负载均衡设置示例: 第一个server如果是本机，就保持使用 spring 不变, 其他 server 就用其他服务器的内网IP
# upstream backend_spring {
#     server spring:8080;
#     server 10.0.0.5:8080;
#     # server 10.0.0.6:8080;
# }

## spring
location /spring {
    # proxy_pass http://spring:8080;
}
location /spring-ui {
    # proxy_pass http://spring:8081;
}

## nodejs
location /nodejs {
    # proxy_pass http://nodejs:8080;
}

location /go-uri/ {
    # proxy_pass http://golang:5000;
}

## 禁止访问的URI
# location /xxxxx {
#     return 404;
# }

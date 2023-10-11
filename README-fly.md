[TOC]

## 硬件/服务器/网络/配置推荐
| 服务器        | 配置推荐                                         |
|:--------------|:-------------------------------------------------|
| CPU 处理器    | >= 2 core(核)                                    |
| MEM 内存      | >= 8 GB                                          |
| Disk 系统硬盘 | >= 60 GB                                         |
| Net 网络带宽  | >= 100M(按量付费) >= 10M(固定带宽付费)           |
| 私有云        | 带宽请自行根据实际业务情况配置网络带宽           |
| 公有云费用    | 初期： 建议所有采购使用“按量付费”(一周？/一月？) |
| 公有云费用    | 初期后： 根据账单决定采购“固定消费”套餐          |
| 防火墙/安全组 | 开放TCP端口 22/80/443                            |

## 软件/系统/版本推荐
| 软件      | 配置推荐                                                               |
|:----------|:-----------------------------------------------------------------------|
| Nginx     | >= 1.18                                                                |
| PHP       | >= 7.1 (CPU >=2核，内存 >=2GB，存储 >=20GB)                            |
| JDK       | >= 1.8 (CPU >=2核，内存 >=2GB，存储 >=20GB) (openjdk/amazoncorretto)   |
| MySQL     | >= 5.7 (CPU >=2核，内存 >=2GB，存储 >=20GB)                            |
| Redis     | >= 7.0 (CPU >=1核，内存 >=1GB，存储 >=20GB)                            |
| OS/单机   | Ubuntu 22.04 (推荐), CentOS/Anolis OS/RedHat/Debian/Rocky 等 Linux |
| OS/集群   | Kubernetes (根据云厂商自动推荐的OS/lifseaOS等/或自行安排)                  |
| OS/不推荐 | windows 系统                                                           |


## 推荐方式一/单机/多机docker-compose部署参考
```sh

## 假如服务器需要代理访问公网，则设置环境变量
# export http_proxy=http://x.x.x.x:1080
# export https_proxy=http://x.x.x.x:1080

## 1. 默认部署环境， docker/nginx/redis/mysql/php-7.1/jdk-1.8
## 2. 默认安装路径， $HOME/docker/laradock 或 $PWD/docker/laradock
## 3. 默认下载并导入 php-fpm 镜像，其他镜像自动使用 docker build 创建
## 4. 访问不到 hub.docker.com 等网络问题，后面加跟参数 "get-image-cdn"
## PHP 单实例(不包含cache/db)： nginx/php 请执行
curl -fL https://gitee.com/xiagw/laradock/raw/in-china/fly.sh | bash -s nginx php
## PHP 套装(包含cache/db)： nginx/php/redis/mysql 请执行
curl -fL https://gitee.com/xiagw/laradock/raw/in-china/fly.sh | bash -s nginx php redis mysql
## Java 单实例(不包含cache/db)： nginx/java 请执行
curl -fL https://gitee.com/xiagw/laradock/raw/in-china/fly.sh | bash -s nginx java
## Java 套装(包含cache/db)： nginx/java/redis/mysql 请执行
curl -fL https://gitee.com/xiagw/laradock/raw/in-china/fly.sh | bash -s nginx java redis mysql
## 所有套装 nginx/php/java/redis/mysql 请执行
# curl -fL https://gitee.com/xiagw/laradock/raw/in-china/fly.sh | bash -s nginx java php-fpm redis mysql

```

### 单机docker部署方式站点URL对应服务器目录说明
| 站点 URL 目录                    | 对应服务器文件系统目录                    |
|:---------------------------------|:------------------------------------------|
| https://www.xxx.com/             | $HOME/docker/html/                        |
| 前端：(VUE/TS 静态文件)          | 若开启静态内容的 CDN 则只需针对此目录开启 |
| https://www.xxx.com/s/           | $HOME/docker/html/s/                      |
| https://www.xxx.com/static/      | $HOME/docker/html/static/                 |
| 后端：(PHP 文件存放目录)         | （可多个项目）                            |
| https://www.xxx.com/tp/php-app01 | $HOME/docker/html/tp/php-app01            |
| https://www.xxx.com/tp/php-app02 | $HOME/docker/html/tp/php-app02            |
| https://www.xxx.com/tp/php-app03 | $HOME/docker/html/tp/php-app03            |
| 后端：(Jar 文件存放目录)         | （可多个jar文件）                         |
| https://www.xxx.com/spring-uri/  | $HOME/docker/laradock/spring/             |


| nginx 配置 | 对应服务器文件系统目录             |
|:-----------|:-----------------------------------|
| nginx 配置 | $HOME/docker/laradock/nginx/sites/ |
| nginx 日志 | $HOME/docker/laradock/logs/nginx/  |


### 操作docker容器简要方式
```sh
## !!! 必须进入此目录 !!! 操作容器
cd $HOME/docker/laradock
## cd $PWD/docker/laradock

## 启动服务 php-fpm
docker compose up -d nginx redis mysql php-fpm
## 启动服务 java (spring)
docker compose up -d nginx redis mysql spring

## 恢复文件权限
sudo chown -R $USER:$USER $HOME/docker/html/static $HOME/docker/html/tp
## PHP 容器内 uid=33
sudo chown -R 33:33 $HOME/docker/html/tp/runtime $HOME/docker/html/tp/*/runtime
## Java 容器内 uid=1000
sudo chown -R 1000:1000 $HOME/docker/laradock/spring

## 如果有负载均衡，单台/多台服务器
1. 设置服务器组（单台/多台）
1. 设置负载均衡监听端口 80/443，指向服务器组
1. 若有安全组则需设置安全组开放 80/443

```

## 推荐方式二/K8S集群helm部署参考
```sh
## 1. 前提条件，确保命令 kubectl / helm 工作正常
## 2. 使用命令 helm create <your_app_name> 生成 helm 文件， 例如:
cd /path/to/helm/
helm create your_app_name

## 3. 根据需要自行修改 your_app_name/*.yml 文件，或使用软件服务商提供的 yml 文件
## 4. 执行 k8s 部署
helm upgrade spring  /path/to/helm/your_app_name/  --install  --history-max 1 \
--namespace dev --create-namespace \
--set image.repository=registry-vpc.cn-hangzhou.aliyuncs.com/ns/repo \
--set image.tag=spring-b962e447-1669878102 \
--set image.pullPolicy=Always --timeout 120s

## 5. 使用 helm/kubectl 或 k9s 查看/操作 pods/services
helm -n dev list
kubectl -n dev get all
```

## 不推荐方式三/单机/多机传统方式部署参考
```sh
### 安装 jdk (参考)
# yum install -y java-1.8.0-openjdk
apt install -y openjdk-18-jdk
### 安装 nginx (参考)
# yum install -y epel-release; yum install -y nginx
apt install -y nginx
### 安装 php71 (参考)
## 安装yum仓库
yum -y install http://rpms.remirepo.net/enterprise/remi-release-7.rpm
## 安装php71
yum -y install php71 php71-php php71-php-fpm php71-php-gd php71-php-json php71-php-mbstring php71-php-mysqlnd php71-php-xml php71-php-xmlrpc php71-php-redis php71-php-pecl-mongodb php71-php-pecl-imagick php71-php-mcrypt php71-php-bcmath php71-php-gmp php71-php-pecl-mysql php71-php-pecl-zip php71-php-soap php71-php-process php71-php-gnupg php71-php-amqp php71-php-opcache
## 启动 php-fpm
systemctl start php71-php-fpm
### 安装 Mysql-5.7 (参考)
## 下载 yum 源
wget -i -c http://dev.mysql.com/get/mysql57-community-release-el7-10.noarch.rpm
## 安装 yum 源
yum -y install mysql57-community-release-el7-10.noarch.rpm
## 安装 mysql-5.7
yum -y install mysql-community-client mysql-community-devel mysql-community-libs mysql-community-server
## 启动 mysql
systemctl start mysqld
### 安装 Redis-4.0 (参考)
yum -y install redis
## 启动 redis
systemctl start redis
### java 程序启动 (参考)
# 启动 jar
exec run.sh start
```

## 不推荐部署于Windows服务器
1. Download URL: https://cdn.flyh6.com/docker/xampp.zip
1. Windows 服务器一般使用 xampp 部署 PHP 项目和前端静态文件
1. 文件存放一般位于 C:\xampp\htdocs\ （此目录对应站点根目录，例如 http://xxx.yyy.com/）
1. C:\xampp\htdocs\tp\ (PHP 代码文件)（此目录对应站点目录，例如 http://xxx.yyy.com/tp/）
1. C:\xampp\htdocs\static\ (前端静态资源文件)（此目录对应站点目录，例如 http://xxx.yyy.com/static/）
1. C:\xampp\spring\ 安装 JDK， 部署 jar 文件
```bat
curl.exe -LO https://cdn.flyh6.com/docker/xampp.zip
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive .\xampp.zip C:\xampp\"
```


## 公网传送临时文件-非加密传输
- 文件非机密内容，可以公开传送
- 文件敏感性低的可以压缩文件并加复杂密码
- 禁止传递敏感性高的文件

奶牛快传｜免费大文件传输工具上传下载不限速 CowTransfer
https://cowtransfer.com/

Wormhole - 简单、私密的文件共享
https://wormhole.app/1PZKN#ti-XEHaU2ZpXi6MHctjVxg

文叔叔 - 传文件，找文叔叔（大文件、永不限速）
https://www.wenshushu.cn/

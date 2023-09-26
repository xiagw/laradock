[TOC]

## 服务器/网络/配置推荐
- CPU 处理器     >= 2 core(核)
- MEM 内存       >= 8 GB
- Disk 系统硬盘   >= 60 GB
- Net 网络带宽    >= 100M(按量付费) ， 或 网络带宽 >= 10M(固定带宽付费)
- 非云服务器，带宽请自行根据实际业务情况配置网络带宽
- 建议所有采购项目初期使用“按量付费”，之后再根据每日账单确定采购“固定消费”套餐
- 防火墙/安全组/开放端口 22/80/443

## 软件/系统/版本
- (单机)操作系统： Ubuntu 22.04(推荐), CentOS, Anolis OS, RedHat, Debian, Rocky 等 Linux 系统
- (集群)操作系统： Kubernetes (根据云厂商自动推荐lifseaOS/或自行安排)
- 极不推荐 windows 系统
- Nginx >= 1.18
- PHP   >= 7.1 (CPU >=2核，内存 >=2GB，存储 >=20GB)
- JDK   >= 1.8 (CPU >=2核，内存 >=2GB，存储 >=20GB)
- JDK 推荐 openjdk 或 amazoncorretto
- MySQL >= 5.7 (CPU >=2核，内存 >=2GB，存储 >=20GB)
- Redis >= 5.0 (CPU >=1核，内存 >=1GB，存储 >=20GB)


## 部署方式一-容器/单机/多机docker-compose部署参考-推荐
```sh
## 假如需要代理
# export http_proxy=http://x.x.x.x:1080
# export https_proxy=http://x.x.x.x:1080
## 安装环境, docker/php-7.1/jdk-1.8 默认安装路径为当前 $PWD/docker/laradock 或 $HOME/docker/laradock
## 默认：1. 下载并导入php-fpm镜像 ；2. 其他镜像使用 docker build 创建 3. 如遇docker hub问题需下载所有镜像 后面加跟参数 download_image
curl -fsSL https://gitee.com/xiagw/laradock/raw/in-china/fly.sh | bash -s nginx php redis mysql
curl -fsSL https://gitee.com/xiagw/laradock/raw/in-china/fly.sh | bash -s nginx java redis mysql
```


## 站点与服务器目录说明
|  站点 URL 目录  | 对应服务器文件系统目录 |
| :------------ | :------------ |
| https://www.xxx.com/ | $HOME/docker/html/ |
| 前端： VUE/TS 前端静态文件  | 若开启静态内容的 CDN 则只需针对此目录开启 |
| https://www.xxx.com/static/ | $HOME/docker/html/static/ |
| https://www.xxx.com/s/ |  $HOME/docker/html/s/ |
| 后端： PHP 文件存放目录 | （可多个项目） |
| https://www.xxx.com/tp/php-app01 | $HOME/docker/html/tp/php-app01 |
| https://www.xxx.com/tp/php-app02 | $HOME/docker/html/tp/php-app02 |
| https://www.xxx.com/tp/php-app03 | $HOME/docker/html/tp/php-app03 |
| 后端： Jar 程序文件存放目录 | （可多个jar文件） |
| https://www.xxx.com/spring-uri/ | $HOME/docker/laradock/spring/ |


|  配置类型  | 配置文件对应服务器文件系统目录 |
| :------------ | :------------ |
| nginx | $HOME/docker/laradock/nginx/sites/ |
| nginx 日志 | $HOME/docker/laradock/logs/nginx/ |


### 服务器操作容器简要方式
```sh
## !!! 必须进入此目录 !!! 操作容器
cd $HOME/docker/laradock
## 或 cd $PWD/docker/laradock
## 启动服务 php-fpm
docker compose up -d nginx redis mysql php-fpm
## 启动服务 java (spring)
docker compose up -d nginx redis mysql spring

##  恢复文件权限
sudo chown -R $USER:$USER $HOME/docker/html/static $HOME/docker/html/tp
sudo chown -R 33:33 $HOME/docker/html/tp/runtime $HOME/docker/html/tp/*/runtime
sudo chown -R 1000:1000 $HOME/docker/laradock/spring

## 如果有负载均衡，单台/多台服务器
1. 设置服务器组（单台/多台）
1. 设置负载均衡监听端口 80/443，指向服务器组
1. 若有安全组则需设置安全组

```

## 部署方式二-容器/K8S集群-helm-部署参考-推荐
```sh
## 1. 前提条件，确保命令 kubectl / helm 工作正常
## 2. 使用命令 helm create <project_name> 生成 helm 文件， 例如:
cd /path/to/helm/
helm create project_app

## 3. 根据需要自行修改 project_app/*.yml 文件，或使用软件服务商提供的 yml 文件
## 4. 执行 k8s 部署
helm upgrade spring  /path/to/helm/project_app/  --install  --history-max 1 \
--namespace dev --create-namespace \
--set image.repository=registry-vpc.cn-hangzhou.aliyuncs.com/ns/repo \
--set image.tag=spring-b962e447-1669878102 \
--set image.pullPolicy=Always --timeout 120s
## 5. 使用 helm/kubectl 或 k9s 查看/操作 pods/services
helm -n dev list
kubectl -n dev get all
```

## 部署方式三-单机/多机传统方式部署参考-不推荐
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

## Windows服务器部署
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


## 传递临时文件/在线公开方式-非加密传输
- 文件非机密内容，可以公开传送
- 文件敏感性低的可以压缩文件并加复杂密码
- 禁止传递敏感性高的文件

奶牛快传｜免费大文件传输工具上传下载不限速 CowTransfer
https://cowtransfer.com/

Wormhole - 简单、私密的文件共享
https://wormhole.app/1PZKN#ti-XEHaU2ZpXi6MHctjVxg

文叔叔 - 传文件，找文叔叔（大文件、永不限速）
https://www.wenshushu.cn/

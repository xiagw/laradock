[TOC]

## 硬件/服务器/网络/配置推荐
| 服务器        | 配置推荐                                      |
|:--------------|:-------------------------------------------|
| CPU 处理器    | >= 2 core(核)                                |
| MEM 内存      | >= 8 GB                                      |
| Disk 系统硬盘 | >= 50 GB                                      |
| Net 网络带宽  | >= 50M(按量付费) >= 10M(固定带宽付费)           |
| 私有云        | 带宽请自行根据实际业务情况配置网络带宽              |
| 公有云费用    | 初期： 建议所有采购使用“按量付费”观察时间(一周/一月)  |
| 公有云费用    | 初期后： 根据账单决定采购“固定消费”套餐(一月/一年)    |
| 防火墙/安全组 | 开放TCP端口 22/80/443                           |


## 业务并发量服务器套餐推荐
| 业务并发量 | 服务器套餐推荐（CPU/MEM/DISK/NETWORK）              |
|:----------|:------------------------------------------------|
| 最低配置   | 2C/8G/50G/50M   应用程序+数据库+缓存，单台           |
| 1000 tps  | 4C/8G/100G/100M 应用程序2台，数据库2台，缓存redis1台 |
| 3000 tps  | 4C/8G/100G/100M 应用程序6台，数据库2台，缓存redis1台 |
| 5000 tps  | 4C/8G/100G/100M 应用程序10台，数据库2台，缓存redis1台 |



## 软件/中间件/操作系统/版本推荐
| 软件      | 配置推荐                                                               |
|:----------|:---------------------------------------------------------------------|
| Nginx     | >= 1.18                                                              |
| PHP       | >= 7.1 (CPU >=2核，内存 >=2GB，存储 >=20GB)                            |
| JDK       | >= 1.8 (CPU >=2核，内存 >=2GB，存储 >=20GB) (openjdk/amazoncorretto)   |
| MySQL     | >= 5.7 (CPU >=2核，内存 >=2GB，存储 >=20GB)                            |
| Redis     | >= 7.0 (CPU >=1核，内存 >=1GB，存储 >=20GB)                            |
| OS/单机   | Ubuntu 22.04 (推荐), CentOS/Anolis OS/RedHat/Debian/Rocky 等 Linux     |
| OS/集群   | Kubernetes (根据云厂商自动推荐的OS/lifseaOS等/或自行安排)                  |
| OS/不推荐 | windows 系统                                                           |


## 推荐方式一/单机/多机docker-compose部署文档
```sh

## 假如服务器需要代理访问公网，则设置环境变量
# export http_proxy=http://x.x.x.x:1080
# export https_proxy=http://x.x.x.x:1080

## 1. 默认部署环境， docker/nginx/redis/mysql/php-7.1/jdk-1.8
## 2. 默认安装路径， $HOME/docker/laradock 或 $PWD/docker/laradock
## 3. 默认下载并导入 php-fpm 镜像，其他镜像自动使用 docker build 创建
## 4. 访问不到 hub.docker.com 等网络问题，后面加参数 "pull-image-all"
## 单例 nginx/php 请执行
curl -fL https://gitee.com/xiagw/laradock/raw/in-china/fly.sh | bash -s php nginx
## 套装 nginx/php/redis/mysql 请执行
curl -fL https://gitee.com/xiagw/laradock/raw/in-china/fly.sh | bash -s php redis mysql nginx
## 单例 nginx/java 请执行
curl -fL https://gitee.com/xiagw/laradock/raw/in-china/fly.sh | bash -s java nginx
## 套装 nginx/java/redis/mysql 请执行
curl -fL https://gitee.com/xiagw/laradock/raw/in-china/fly.sh | bash -s java redis mysql nginx
## 套装 nginx/php/java/redis/mysql 请执行
curl -fL https://gitee.com/xiagw/laradock/raw/in-china/fly.sh | bash -s java php-fpm redis mysql nginx

```

### 单机docker部署方式站点URL对应服务器目录说明
| 站点 URL 目录                    | 对应服务器文件系统目录                                              |
|:---------------------------------|:--------------------------------------------------------------------|
| https://www.xxx.com/             | $HOME/docker/html/                                                  |
| 前端：(VUE/TS 等静态文件)        | 若开启静态内容的 CDN 则只需针对此目录开启                           |
| https://www.xxx.com/s1/          | $HOME/docker/html/s1/                                               |
| https://www.xxx.com/s2/          | $HOME/docker/html/s2/                                               |
| https://www.xxx.com/static/      | $HOME/docker/html/static/                                           |
| 后端：(PHP 文件存放目录)         | （可多个项目）                                                      |
| https://www.xxx.com/tp/php-app01 | $HOME/docker/html/tp/php-app01                                      |
| https://www.xxx.com/tp/php-app02 | $HOME/docker/html/tp/php-app02                                      |
| https://www.xxx.com/tp/php-app03 | $HOME/docker/html/tp/php-app03                                      |
| 后端：(Jar 文件存放目录)         | （可存放多个jar文件/log文件也在此）                                 |
| https://www.xxx.com/uri/         | $HOME/docker/laradock/spring/                                       |
| https://www.xxx.com/uri2/        | $HOME/docker/laradock/spring2/                                      |
| https://www.xxx.com/             | $HOME/docker/html/  (本地存储文件路径)     (容器内为/var/www/html/) |
| 后端：(NodeJS 文件存放目录)      | （可多个项目目录）（node_modules 不用上传）                         |
| https://www.xxx.com/node-uri/    | $HOME/docker/laradock/nodejs/        (容器内为/app/)                |
| https://www.xxx.com/node-uri2/   | $HOME/docker/laradock/nodejs2/      (容器内为/app/)                 |
| Nginx：目录配置和日志               | （可多个站点配置）                                                    |
| nginx conf 配置文件路径            | $HOME/docker/laradock/nginx/sites/                                  |
| nginx SSL 证书文件路径             | $HOME/docker/laradock/nginx/sites/ssl                               |
| nginx 日志文件存放路径              | $HOME/docker/laradock/logs/nginx/                                   |
| redis 数据存放路径                 | $HOME/laradock-data/redis/                                          |
| mysql 数据存放路径                 | $HOME/laradock-data/mysql/                                          |
| mysql 数据备份路径                 | $HOME/laradock-data/mysqlbak/                                       |


### 操作docker容器简要方式/查看日志
```sh
## 操作容器 !!! 必须进入此目录 !!!
cd $HOME/docker/laradock  ## 或 ## cd $PWD/docker/laradock

##  查看 mysql/redis 信息  ！！！注意 ！！！
## 1，如果客户没有单独的 db / redis，则使用本服务器的db/redis ，用此方式查看 mysql, redis 的链接/账号/密码/信息
## 2，如果客户有独立的 db / redis ，则不需要查看此信息（独立mysql redis 不从此查看）
cd $HOME/docker/laradock && bash fly.sh info

cd $HOME/docker/laradock && docker compose up -d nginx redis mysql php-fpm      ## 启动服务 php-fpm
cd $HOME/docker/laradock && docker compose up -d nginx redis mysql spring       ## 启动服务 Java (spring)
cd $HOME/docker/laradock && docker compose up -d nginx redis mysql nodejs       ## 启动服务 Nodejs
cd $HOME/docker/laradock && docker compose stop nginx redis mysql php-fpm      ## 停止服务 php-fpm
cd $HOME/docker/laradock && docker compose stop nginx redis mysql spring       ## 停止服务 Java (spring)
cd $HOME/docker/laradock && docker compose stop nginx redis mysql nodejs       ## 停止服务 nodejs

cd $HOME/docker/laradock && docker compose logs -f --tail 100 spring       ## java 查看容器日志最后 100 行
cd $HOME/docker/laradock && tail -f spring/*.log          ## 如果程序写入 log 文件，也可以查看 spring/*.log 文件

## java / nodejs 修改 nginx 配置文件  $HOME/docker/laradock/nginx/sites/router.inc
cd $HOME/docker/laradock && docker compose exec nginx nginx -s reload       ## nginx 重启 (修改配置文件后必须重启)
cd $HOME/docker/laradock && docker compose logs -f --tail 100 nginx       ## nginx 查看容器日志最后 100 行

## 替换 Nginx SSL 证书 key 文件 $HOME/docker/laradock/nginx/sites/ssl/default.key
## 替换 Nginx SSL 证书 pem 文件 $HOME/docker/laradock/nginx/sites/ssl/default.pem

## mysql 导入文件，把sql文件存放到目录 / 文件名: $HOME/laradock-data/mysqlbak/db.sql
## 导入数据库文件（使用本服务器的db/redis）（独立mysql redis 不从此操作）
cd $HOME/docker/laradock && docker compose exec mysql bash -c  'mysql -udefaultdb -p defaultdb </backup/db.sql'

## mysql 进入命令行操作
cd $HOME/docker/laradock && docker compose exec mysql bash -c "LANG=C.UTF8 mysql defaultdb"

## redis 进入命令行操作
cd $HOME/docker/laradock && docker compose exec redis redis-cli

## 如果SSH登陆服务器为非root帐号，先上传文件到 $HOME/xxx.jar，然后再转移到 $HOME/docker/laradock/spring
sudo mv $HOME/xxx.jar  $HOME/docker/laradock/spring/

## 文件权限
sudo chown -R $USER:$USER $HOME/docker/html/static $HOME/docker/html/tp    ## 恢复文件权限
sudo chown -R 33:33 $HOME/docker/html/tp/runtime $HOME/docker/html/tp/*/runtime    ## PHP 容器内 uid=33
sudo chown -R 1000:1000 $HOME/docker/laradock/spring    ## Java 容器内 uid=1000
sudo chown -R 1000:1000 $HOME/docker/html/uploads       ## Java 容器内 uid=1000 对应容器内目录 /var/www/html/uploads
sudo chown -R 1000:1000 $HOME/docker/laradock/nodejs    ## Nodejs 容器内 uid=1000

## 如果有负载均衡，单台或多台服务器
1. 设置负载均衡服务器组（单台/多台）
1. 设置负载均衡监听端口 80/443，指向服务器组
1. 若有安全组则需设置安全组开放 80/443

```

## 推荐方式二/K8S集群kubectl/helm部署参考
```sh
## 1. 前提条件，确保命令 kubectl / helm 工作正常
## 2. 使用命令 helm create <your_app_name> 生成 helm 文件， 例如:
cd /path/to/helm/
helm create your_app_name

## 3. 根据需要自行修改 your_app_name/*.yml 文件，或使用软件服务商提供的 yml 文件
## 4. 执行 k8s 部署
helm upgrade --install --atomic --history-max 3 \
--namespace dev --create-namespace \
your_app_name /path/to/helm/your_app_name/ \
--set image.repository=registry-vpc.cn-hangzhou.aliyuncs.com/ns/repo \
--set image.tag=spring-b962e447-1669878102 \
--set image.pullPolicy=Always --timeout 120s

## 5. 使用 helm/kubectl 或 k9s 查看/操作 pods/services
helm -n dev list
kubectl -n dev get all
```


## 不推荐部署于Windows服务器
1. Download URL: http://oss.flyh6.com/d/xampp.zip
1. Windows 服务器一般使用 xampp 部署 PHP 项目和前端静态文件

| 站点 URL 目录                     | 对应服务器文件系统目录                        |
|:---------------------------------|:------------------------------------------|
| http://xxx.yyy.com/ | C:\xampp\htdocs\ |
| http://xxx.yyy.com/tp/ | C:\xampp\htdocs\tp\ (PHP 代码文件) |
| http://xxx.yyy.com/s/ | C:\xampp\htdocs\s\ (前端静态资源文件) |
| http://xxx.yyy.com/spring-xxx/ | C:\xampp\spring\ （安装 JDK， 部署 jar 文件） |

```sh
cd .\Downloads

# irm https://gitee.com/xiagw/deploy.sh/raw/main/docs/bin/win.ssh.ps1 | iex

# Import-Module BitsTransfer
# Start-BitsTransfer -Source http://oss.flyh6.com/d/xampp.zip -Description .\xampp.zip

curl.exe -LO http://oss.flyh6.com/d/xampp.zip
Expand-Archive .\xampp.zip C:\
# powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive .\xampp.zip C:\"

curl.exe -LO https://corretto.aws/downloads/latest/amazon-corretto-8-x64-windows-jdk.msi
Start-Process .\amazon-corretto-8-x64-windows-jdk.msi
# curl.exe -LO https://corretto.aws/downloads/latest/amazon-corretto-17-x64-windows-jdk.msi
# Start-Process .\amazon-corretto-17-x64-windows-jdk.msi
```


## 公网传送临时文件-非加密传输
1. 文件非机密内容，可以公开传送
1. 文件敏感性低的可以压缩文件并加复杂密码
1. 禁止传递敏感性高的文件

| 站点                       | 网址                      |
|:---------------------------|:--------------------------|
| 奶牛快传免费               | https://cowtransfer.com/  |
| Wormhole简单私密的文件共享 | https://wormhole.app/     |
| 文叔叔                     | https://www.wenshushu.cn/ |


## 查询域名备案
1. https://beian.miit.gov.cn/#/Integrated/recordQuery

# Bitvise教程/下载/安装软件
1. 下载方式一， [BvSshClient http://oss.flyh6.com/d/BvSshClient-Inst.zip](http://oss.flyh6.com/d/BvSshClient-Inst.zip)
1. 下载方式二， [BvSshClient https://www.putty.org/](https://www.putty.org/)

# Bitvise密码/登录服务器
1.  `假如无法使用密码，则需用SSH Key登录`
1. 从管理员/客户处获取服务器IP/帐号/密码，
1. 输入 `Host:` IP
1. 输入 `Username:`  帐号
1. 点左下角 `login` , （点击 `Accept and Save`），`输入密码`登录
1. 点击左侧 `New Terminal console` 进入命令行界面
1. 点击左侧 `New SFTP window` 进入文件夹管理界面，可以直接上传/下载文件

# Bitvise拷贝文件到服务器目录
1. 使用以上 `Bitvise SSH Client` 可以拷贝文件到服务器端 目录。
1. 网址对应服务器目录关系，参考本页上方的“### 单机docker部署方式站点URL对应服务器目录说明”
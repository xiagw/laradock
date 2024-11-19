[TOC]

## 硬件/服务器/网络/域名配置推荐
| 服务器        | 配置推荐                                             |
|:--------------|:-----------------------------------------------------|
| CPU 处理器    | >= 4 core(核) (支持AMD/Intel/ARM64)                      |
| MEM 内存      | >= 8 GB                                              |
| Disk 系统硬盘 | >= 50 GB                                             |
| Net 网络带宽  | >= 50M(按量付费) >= 10M(固定带宽付费)                |
| 私有云        | 自行根据实际业务情况配置网络带宽               |
| 公有云费用    | 初始部署：建议充值200-500元使用“按量付费”观察时间(三天/一周/一月)         |
| 公有云费用    | 持续运行：根据账单决定采购“固定”套餐(一月/一年)    |
| 域名数量      | 前/后端各一个共2个域名                                |
| 防火墙/安全组 | 开放TCP端口 22/80/443                                |
| 最低要求配置  | 2C/8G/50G/50M 应用程序+数据库+缓存，单台（t6/u1系列便宜）  |
| 业务并发量    | 服务器套餐推荐（CPU/MEM/DISK/NETWORK）               |
| 1000 tps      | 2C/8G/100G/100M 应用程序2台，数据库2台，缓存redis1台 |
| 3000 tps      | 2C/8G/100G/100M 应用程序4台，数据库2台，缓存redis1台 |
| 5000 tps      | 2C/8G/100G/100M 应用程序6台，数据库2台，缓存redis1台 |



## 软件/中间件/操作系统/版本
| 软件      | 系统/配置推荐                                                             |
|:----------|:---------------------------------------------------------------------|
| Nginx     | >= 1.18                                                              |
| PHP       | >= 7.1 (CPU >=2核，内存 >=2GB，存储 >=20GB)                          |
| JDK       | >= 1.8 (CPU >=2核，内存 >=2GB，存储 >=20GB) (amazoncorretto)        |
| MySQL     | >= 5.7 (CPU >=2核，内存 >=2GB，存储 >=20GB)                          |
| Redis     | >= 7.0 (CPU >=1核，内存 >=1GB，存储 >=20GB)                          |
| OS/单机   | Ubuntu 22.04 (推荐), CentOS/Anolis OS/RedHat/Debian/Rocky 等 Linux   |
| OS/集群   | Kubernetes（推荐） (操作系统根据云厂商自动推荐的OS/lifseaOS等/或自行安排)    |


## 部署方式一：单机/多机docker-compose部署文档
```sh
## 假如服务器需要代理访问公网，则设置环境变量
# export http_proxy=http://x.x.x.x:1080; export https_proxy=http://x.x.x.x:1080

## 1. 默认安装路径， $HOME/docker/laradock 或 $PWD/docker/laradock
## 2. 默认部署环境， docker/nginx-1.2x/redis-7.x/mysql-8.0/php-7.4/openjdk-8
curl -fL https://gitee.com/xiagw/laradock/raw/in-china/fly.sh | bash
## 套装LNMP nginx/php/redis/mysql 请执行
curl -fL https://gitee.com/xiagw/laradock/raw/in-china/fly.sh | bash -s php redis mysql nginx
## 套装Java nginx/java/redis/mysql 请执行
curl -fL https://gitee.com/xiagw/laradock/raw/in-china/fly.sh | bash -s java redis mysql nginx
## 单PHP nginx/php 请执行
curl -fL https://gitee.com/xiagw/laradock/raw/in-china/fly.sh | bash -s php nginx
## 单Java nginx/java 请执行
curl -fL https://gitee.com/xiagw/laradock/raw/in-china/fly.sh | bash -s java nginx
## 单Nodejs nginx/nodejs 请执行
curl -fL https://gitee.com/xiagw/laradock/raw/in-china/fly.sh | bash -s nodejs nginx
```

### 单机docker部署方式站点URL对应服务器目录说明
| 站点 URL 目录                    | 对应服务器文件系统目录                                              |
|:---------------------------------|:--------------------------------------------------------------------|
| https://www.xxx.com/             | $HOME/docker/html/                                                  |
| 前端：(VUE/TS 等静态文件)        | 若开启静态内容的 CDN 则只需针对此目录开启                           |
| https://www.xxx.com/s1/          | $HOME/docker/html/s1/                                               |
| https://www.xxx.com/s2/          | $HOME/docker/html/s2/                                               |
| https://www.xxx.com/static/      | $HOME/docker/html/static/                                           |
| 后端：(PHP 文件存放目录)         | （支持多个不同项目）                                                |
| https://www.xxx.com/tp/php-app01 | $HOME/docker/html/tp/php-app01                                      |
| https://www.xxx.com/tp/php-app02 | $HOME/docker/html/tp/php-app02                                      |
| https://www.xxx.com/tp/php-app03 | $HOME/docker/html/tp/php-app03                                      |
| 后端：(Jar 文件存放目录)         | （支持多个jar文件/log文件也在此）                                   |
| https://www.xxx.com/uri/         | $HOME/docker/laradock/spring/                                       |
| https://www.xxx.com/uri2/        | $HOME/docker/laradock/spring2/                                      |
| https://www.xxx.com/             | $HOME/docker/html/  (本地存储文件路径)     (容器内为/var/www/html/) |
| 后端：(node.js 文件存放目录)     | （支持多个项目目录）（node_modules 不用上传）                       |
| https://www.xxx.com/node-uri/    | $HOME/docker/laradock/nodejs/        (容器内为/app/)                |
| https://www.xxx.com/node-uri2/   | $HOME/docker/laradock/nodejs2/      (容器内为/app/)                 |
| Nginx：目录配置和日志            | （支持多个不同站点配置）                                            |
| nginx conf 配置文件路径          | $HOME/docker/laradock/nginx/sites/                                  |
| nginx 日志文件存放路径           | $HOME/docker/laradock/logs/nginx/                                   |
| redis 数据存放路径               | $HOME/laradock-data/redis/                                          |
| mysql 数据存放路径               | $HOME/laradock-data/mysql/                                          |
| mysql 数据备份路径               | $HOME/laradock-data/mysqlbak/                                       |


### 操作docker容器简要方式/查看日志
```sh
## ！！！ 必须进入此目录 ！！！
cd $HOME/docker/laradock  ## 或 ## cd $PWD/docker/laradock

## ！！！ 注意 ！！！
## 1，如果客户有独立的 mysql/redis ，则不需要查看此信息（独立 mysql/redis 信息不从此查看）
## 2，如果客户没有单独的 mysql/redis，则使用此方式查看本服务器 mysql/redis 的链接/账号/密码/信息
## 3，容器内和代码内写标准端口 mysql=3306/redis=6379，此处显示端口只用于远程 SSH 端口转发映射
cd $HOME/docker/laradock && bash fly.sh info

cd $HOME/docker/laradock && docker compose stop redis mysql php-fpm nginx      ## 停止服务 php-fpm
cd $HOME/docker/laradock && docker compose stop redis mysql spring nginx       ## 停止服务 Java (spring)
cd $HOME/docker/laradock && docker compose stop redis mysql nodejs nginx       ## 停止服务 nodejs

cd $HOME/docker/laradock && docker compose up -d redis mysql php-fpm nginx      ## 启动服务 php-fpm
cd $HOME/docker/laradock && docker compose up -d redis mysql spring nginx       ## 启动服务 Java (spring)
cd $HOME/docker/laradock && docker compose up -d redis mysql nodejs nginx       ## 启动服务 Nodejs

cd $HOME/docker/laradock && docker compose logs -f --tail 100 spring       ## java 查看容器日志最后 100 行
cd $HOME/docker/laradock && tail -f spring/*.log          ## 查看文件夹内 spring/*.log 文件

## 替换 Nginx SSL 证书 key 文件 $HOME/docker/laradock/nginx/sites/ssl/default.key
## 替换 Nginx SSL 证书 pem 文件 $HOME/docker/laradock/nginx/sites/ssl/default.pem
## java / nodejs 修改 nginx 配置文件  $HOME/docker/laradock/nginx/sites/router.inc
cd $HOME/docker/laradock && docker compose exec nginx nginx -s reload     ## nginx 重启 (修改配置文件后必须重启)
cd $HOME/docker/laradock && docker compose logs -f --tail 100 nginx       ## nginx 查看容器日志最后 100 行

## 新增 spring 或 nodejs 容器
## 1. 复制文件夹 spring 到新文件夹，例如 spring3（nodejs 同理）
## 2. 修改 docker-compose.override.yml，复制 spring 段落到新段落，改名，例如 spring3（nodejs 同理）
## 3. 修改 nginx 配置文件 router.inc（nodejs 同理）

## 1. sql文件存放目录/文件名: $HOME/laradock-data/mysqlbak/db.sql
## 2. 导入数据库文件（使用本服务器的 mysql/redis）（独立非本机 mysql/redis 不从此操作）
cd $HOME/docker/laradock && docker compose exec mysql bash -c 'mysql -udefaultdb -p defaultdb </backup/db.sql'
## mysql 进入命令行操作(本机)
cd $HOME/docker/laradock && docker compose exec mysql bash -c "LANG=C.UTF8 mysql defaultdb"
## mysql 进入命令行操作(远程)
cd $HOME/docker/laradock && docker compose exec mysql bash -c "LANG=C.UTF8 mysql -h'xxxxx' -u'yyyyyy' -p'zzzzzz'"
## redis 进入命令行操作(本机)
cd $HOME/docker/laradock && docker compose exec redis bash -c "LANG=C.UTF8 redis-cli -a'zzzzzz'"
## redis 进入命令行操作(远程)
cd $HOME/docker/laradock && docker compose exec redis bash -c "LANG=C.UTF8 redis-cli -h'xxxxx' -a'zzzzzz'"

## 如果 SSH 登陆服务器为非 root 帐号，先上传文件到 $HOME/xxx.jar，然后再转移到 $HOME/docker/laradock/spring
# sudo mv $HOME/xxx.jar  $HOME/docker/laradock/spring/
sudo chown -R $USER:$USER $HOME/docker/html/static $HOME/docker/html/tp    ## 恢复文件权限
sudo chown -R 33:33 $HOME/docker/html/tp/runtime $HOME/docker/html/tp/*/runtime    ## PHP 容器内 uid=33
sudo chown -R 33:33 $HOME/docker/html/upload_php       ## PHP 容器内 uid=33 对应容器内目录 /var/www/html/upload_php
sudo chown -R 1000:1000 $HOME/docker/laradock/spring    ## Java 容器内 uid=1000
sudo chown -R 1000:1000 $HOME/docker/html/uploads       ## Java 容器内 uid=1000 对应容器内目录 /var/www/html/uploads
sudo chown -R 1000:1000 $HOME/docker/laradock/nodejs    ## Nodejs 容器内 uid=1000

## 如果有负载均衡，单台或多台服务器
1. 设置负载均衡监听端口 80/443，指向服务器组（单台/多台）
2. 若有安全组或防火墙则需设置安全组开放 80/443

```

## 部署方式二：K8S集群kubectl/helm部署参考
```sh
## 1. 前提条件，确保命令 kubectl / helm 工作正常，可以正常操作 k8s 集群
## 2. 使用命令 helm create <your_app_name> 生成 helm 文件
cd /path/to/helm/ && helm create your_app_name
## 3. 根据需要自行修改 your_app_name/*.yml 文件，或使用软件服务商提供的 yml 文件
## 4. 执行 k8s 部署
helm upgrade --install --atomic --history-max 3 \
--namespace dev --create-namespace \
your_app_name /path/to/helm/your_app_name/ \
--set image.pullPolicy=Always --timeout 120s \
--set image.repository=registry-vpc.cn-hangzhou.aliyuncs.com/ns/repo \
--set image.tag=spring-b962e447-1669878102
## 5. 使用 helm/kubectl 或 k9s 查看/操作 pods/services
helm -n dev list
kubectl -n dev get all
```


## 不建议部署于Windows服务器
1. Windows 服务器不适合安装redis，Windows 兼容性较差，以及与docker兼容性较差，不建议使用Windows服务器


## 公网传送临时文件-非加密传输
1. 文件非机密内容，可以公开传送
1. 文件敏感性低的可以压缩文件并加复杂密码
1. 禁止传递敏感性高的文件

| 站点                       | 网址                      |
|:---------------------------|:--------------------------|
| 奶牛快传免费               | https://cowtransfer.com/  |
| Wormhole简单私密的文件共享  | https://wormhole.app/     |
| 文叔叔                     | https://www.wenshushu.cn/ |


## 查询域名备案
1. 公共查询备案： https://beian.miit.gov.cn/#/Integrated/recordQuery
1. 阿里云ICP备案： https://beian.aliyun.com/ （建议下载它的App进行备案速度更快）
1. “备案提供商”和“服务器提供商”必须一致，例如“阿里云备案”则必须是“阿里云服务器”，例如腾讯云服务器+阿里云备案是无效的。（域名在哪里和备案无关）
1. 服务器在中国内地需要域名备案，港澳台和外国无需域名备案，【如果没有备案必须先去“**服务器提供商**”备案】

# Bitvise教程/下载/安装软件/登录服务器/拷贝文件到服务器目录
1. 下载方式一， [BvSshClient http://oss.flyh6.com/d/BvSshClient-Inst.zip](http://oss.flyh6.com/d/BvSshClient-Inst.zip)
1. 下载方式二， [BvSshClient https://www.putty.org/](https://www.putty.org/)
1. 假如无法使用密码，则需用SSH Key登录
1. 从管理员/客户处获取服务器IP/帐号/密码，
1. 输入 `Host:` IP ，输入 `Username:`  帐号
1. 点左下角 `login` , （点击 `Accept and Save`），`输入密码`登录
1. 点击左侧 `New Terminal console` 进入命令行界面
1. 点击左侧 `New SFTP window` 进入文件夹管理界面，可以直接上传/下载文件
1. 网址对应服务器目录关系，参考本页上方的“### 单机docker部署方式站点URL对应服务器目录说明”

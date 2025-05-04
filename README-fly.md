[TOC]

## 硬件/服务器/网络/域名配置推荐
| 项目          | 配置要求  |
|:--------------|:-------------------------------------------------|
| CPU/处理器     | ≥4核 (AMD/Intel/ARM64) |
| MEM/内存       | ≥8GB |
| DISK/硬盘      | ≥50GB |
| NET/网络带宽   | ≥50M |
| 域名          | 前后端各1个，配SSL证书 |
| 安全设置      | 开放端口：22/80/443 (TCP)|
| 计费方式      | 1. 初期：按量付费(建议充值200-500元)；2. 稳定后：固定套餐(月付/年付) |


## 服务器配置推荐
| 业务规模 | 基础配置 | 单机/集群配置 |
|:--------|:---------|:---------|
| 标准型   | 2C/8G/50G/50M | 单机部署（最低要求） |
| 高性能型 | 2C/8G/100G/100M | 应用×2 + 数据库×2 + 缓存×1 (支持1000 TPS) |
| 企业型   | 2C/8G/100G/100M | 应用×4 + 数据库×2 + 缓存×1 (支持3000 TPS) |
| 旗舰型   | 2C/8G/100G/100M | 应用×6 + 数据库×2 + 缓存×1 (支持5000 TPS) |



## 运行环境要求/软件/中间件/操作系统/版本
| 组件      | 最低版本及资源配置                                                  |
|:----------|:------------------------------------------------------------------|
| Nginx     | v1.18+ (2C/2G)                                                     |
| PHP       | v7.1+ (2C/2G/20G)                                                 |
| JDK       | v1.8+ (2C/2G/20G) (amazoncorretto)                               |
| Node.js   | v20+ (2C/2G/20G)                                                  |
| Redis     | v7.0+ (1C/1G/20G)                                                 |
| MySQL     | v8.0+ (2C/2G/20G)                                                 |
| OS/单机    | Ubuntu 22.04 LTS (推荐), CentOS/Anolis/RedHat/Debian/Rocky 等Linux|
| 集群/容器   | Kubernetes (生产环境推荐)                                          |


## 部署方式一：单机/多机docker-compose部署文档
```sh
## 假如服务器需要代理访问公网，则设置环境变量
#export http_proxy=http://x.x.x.x:1080; export https_proxy=http://x.x.x.x:1080
## Aliyun - ECS - 云助手(左下角) - 实例(右侧) - 执行命令 （复制以下命令，超时时间1500秒）
## 1. 默认安装路径， $HOME/docker/laradock 或 $PWD/docker/laradock
## 2. 默认部署环境， docker/nginx-1.2x/redis-7.x/mysql-8.0/php-8.1/openjdk-8
curl -fL https://gitee.com/xiagw/laradock/raw/in-china/fly.sh | bash
```

### 单机docker部署方式站点URL对应服务器目录说明
| 站点/URL/目录                    | 对应服务器文件系统目录/(或容器内目录)                                      |
|:---------------------------------|:--------------------------------------------------------------------|
| https://www.xxx.com/             | $HOME/docker/html/                                                  |
| 前端：(VUE/TS 等静态文件)          | 若开启静态内容的 CDN 则只需针对此目录开启                           |
| https://www.xxx.com/s1/          | $HOME/docker/html/s1/                                               |
| https://www.xxx.com/s2/          | $HOME/docker/html/s2/                                               |
| https://www.xxx.com/static/      | $HOME/docker/html/static/                                           |
| 后端：(PHP)                       | （支持多个不同项目按目录区分）                                           |
| https://www.xxx.com/tp/php-app01 | $HOME/docker/html/tp/php-app01                                      |
| https://www.xxx.com/tp/php-app02 | $HOME/docker/html/tp/php-app02                                      |
| https://www.xxx.com/tp/php-app03 | $HOME/docker/html/tp/php-app03                                      |
| 后端：(Jar)                       | （支持多个jar文件/log文件也在此）                                   |
| https://www.xxx.com/uri/         | $HOME/docker/laradock/spring/                                       |
| https://www.xxx.com/uri2/        | $HOME/docker/laradock/spring2/                                      |
| https://www.xxx.com/             | $HOME/docker/html/  (服务器本机存储文件路径)(容器内为/var/www/html/) |
| 后端：(Nodejs)                    | （支持多个项目目录）（node_modules 不需要上传）                       |
| https://www.xxx.com/node-uri/    | $HOME/docker/laradock/nodejs/        (容器内为/app/)                |
| https://www.xxx.com/node-uri2/   | $HOME/docker/laradock/nodejs2/      (容器内为/app/)                 |
| Nginx：目录配置和日志              | （支持多个不同站点配置）                                            |
| nginx conf 配置文件路径          | $HOME/docker/laradock/nginx/sites/{default.conf, router.inc}      |
| nginx 日志文件存放路径           | $HOME/docker/laradock/logs/nginx/                                   |
| redis 数据存放路径               | $HOME/laradock-data/redis/                                          |
| mysql 数据存放路径               | $HOME/laradock-data/mysql/                                          |
| mysql 数据备份路径               | $HOME/laradock-data/mysqlbak/                                       |


### 操作docker容器简要方式/查看日志
```sh
## ！！！ 必须进入此目录 ！！！
cd $HOME/docker/laradock  ## 或 ## cd $PWD/docker/laradock

## ！！！ 注意 ！！！ 这个是服务器本机集成的 mysql/redis 信息
## 1. 如果客户有独立的 mysql/redis ，则不需要查看此信息（独立 mysql/redis 信息不从此查看）
## 2. 只有当客户没有单独的 mysql/redis，则使用此方式查看本服务器 mysql/redis 的链接/账号/密码/信息
## 3. 容器内和代码内写标准端口 mysql=3306/redis=6379，此处显示端口只用于远程 SSH 端口转发映射
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
## 修改 java 启动参数
## 1. 创建 spring/.java_opts 文件，内容: export JAVA_OPTS="java -Xms1g -Xmx1g"

## 新增 spring 或 nodejs 容器
## 1. 复制文件夹 spring 到新文件夹，例如 spring3（nodejs 同理）
## 2. 修改 docker-compose.override.yml，复制 spring 段落到新段落，改名，例如 spring3（nodejs 同理）
## 3. 复制镜像: docker tag laradock-spring laradock-spring3
## 4. 修改 nginx 配置文件 router.inc（nodejs 同理）

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

## K8S集群部署指南

### 前置条件
- 已配置kubectl和helm客户端工具
- 已获取K8S集群访问权限

### 部署步骤
```sh
# 1. 验证环境
command -v kubectl && command -v helm && echo 'ok' || echo failed
# 2. 创建Helm Chart
helm create myapp
# 3. 配置应用
# 修改 myapp/values.yaml，设置镜像、资源等配置
# 4. 部署应用
helm upgrade --install --atomic --history-max 3 --timeout 120s \
  --namespace dev --create-namespace \
  myapp ./myapp \
  --set image.repository=nginx,image.tag=stable-alpine
# 5. 验证部署
helm ls -n dev
kubectl -n dev get pods,svc
```

### 关键配置说明
- `--atomic`: 原子部署，失败自动回滚
- `--namespace`: 指定部署命名空间
- `--timeout`: 部署超时时间
- 更多配置参见values.yaml文件


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


## 域名配置与ICP备案要求

### ICP备案要求
- 备案范围：仅限中国内地服务器，港澳台及海外无需备案
- 备案原则：必须在服务器提供商处完成备案
- 备案查询：https://beian.miit.gov.cn/#/Integrated/recordQuery
- 阿里云ICP备案： https://beian.aliyun.com/ （建议使用App进行备案速度更快）
### 备案示例
- 有效备案：阿里云服务器 + 阿里云备案
- 无效备案：腾讯云服务器 + 阿里云备案
### 域名配置要求
- DNS解析：配置A记录指向服务器IP
- SSL证书：配置HTTPS证书(Nginx格式)
- 备案验证：确保备案信息与服务器提供商一致



## Bitvise SSH客户端配置指南

### 下载安装
- 官方下载：[Bitvise SSH Client](https://www.putty.org/)
- 镜像下载：[Bitvise SSH Client (国内镜像)](http://oss.flyh6.com/d/BvSshClient-Inst.zip)

### 服务器连接
1. 获取必要信息：服务器IP、用户名和认证方式（密码或SSH密钥）
2. 配置连接：
   - Host：输入服务器IP
   - Port：默认22
   - Username：输入用户名
   - 认证方式：选择密码或SSH密钥
3. 建立连接：点击Login（首次连接需确认服务器指纹）（点击 `Accept and Save`）

### 文件传输
- Terminal：点击`New terminal console`打开命令行界面
- SFTP：点击`New SFTP window`管理文件
- 目录结构：参考上方"单机docker部署方式站点URL对应服务器目录说明"

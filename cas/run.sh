#!/usr/bin/env bash

if [ ! -f /etc/cas/thekeystore ]; then
    echo "Generating keystore"
    keytool -genkey -keyalg RSA -validity 10000 -alias cas \
        -keystore /etc/cas/thekeystore \
        -storepass changeit -keypass changeit \
        -dname "CN=cas, OU=cas, O=cas, L=cas, S=cas, C=cas"
fi

# https://localhost:8445/cas/login
# 官方默认账号登录：
# 用户名：casuser
# 密码：Mellon
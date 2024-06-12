#!/usr/bin/env bash

printf "[client]\npassword=%s\n" "${MYSQL_ROOT_PASSWORD}" >/root/.my.cnf
chmod 600 /root/.my.cnf

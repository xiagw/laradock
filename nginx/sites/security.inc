## 保留旧配置的信息
if ( $deny_host ) { return 403; }
if ( $deny_ua = 2 ) { return 403; }
if ( $deny_ref ) { return 403; }

location ~* /(favicon\.ico|robots\.txt)$ {
    access_log off;
    log_not_found off;
}
# location /.well-known/acme-challenge/ {
#     # root /app/public/letsencrypt/;
#     log_not_found off;
# }
error_page   400 404 /4xx.html;
error_page   500 501 502 503 504  /5xx.html;

location ~* /(.*)\.(htaccess|htpasswd|env|svn|subversion|git|db|sql|sqlite|sqlite3|bak|inc|old|7z|zip|rar|xz|tar|gz|tgz|tar\.gz|log|bashrc|bash_history|cfg|ini|yml|buildpath|project|settings|mdb|frm|\~|asp|aspx|jsp)$ {
    return 403;
}
if ( $request_method !~ ^(GET|POST|PUT|DELETE|OPTIONS)$ ) {
    return 403;
}
if ( $query_string ~* ".*['<>].*" ) {
    return 403;
}
if ($request_uri ~* "(cost\()|(concat\()" ) {
    return 444;
}
if ($request_uri ~* "[+|(%20)]union[+|(%20)]" ) {
    return 444;
}
if ($request_uri ~* "[+|(%20)]and[+|(%20)]" ) {
    return 444;
}
if ($request_uri ~* "[+|(%20)]select[+|(%20)]" ) {
    return 444;
}
if ($request_uri ~* "[+|(%20)]or[+|(%20)]" ) {
    return 444;
}
if ($request_uri ~* "[+|(%20)]delete[+|(%20)]" ) {
    return 444;
}
if ($request_uri ~* "[+|(%20)]update[+|(%20)]" ) {
    return 444;
}
if ($request_uri ~* "[+|(%20)]insert[+|(%20)]" ) {
    return 444;
}

if ($query_string ~* ".*('|shell|bash|tmp|--|union|join|sleep|delete|insert|drop|truncate|update|grant|exec|where|select|and|count|chr|mid|like|iframe|script|alert|webscan|dbappsecurity|style|confirm|innerhtml|innertext|class).*") {
    return 445;
}

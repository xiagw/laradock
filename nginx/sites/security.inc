error_page   400 404 /4xx.html;
error_page   500 501 502 503 504  /5xx.html;

location /.well-known/acme-challenge/ {
    # root /app/public/letsencrypt/;
    log_not_found off;
}
location ~* /(favicon\.ico|robots\.txt)$ {
    access_log off;
    log_not_found off;
}
## 保留旧配置的信息
if ( $deny_host ) { return 444; }
if ( $deny_ua = 2 ) { return 444; }
if ( $deny_ref ) { return 444; }

location ~* /runtime/ { return 444; }

location ~* /(.*)\.(htaccess|htpasswd|env|svn|subversion|git|db|sql|sqlite|sqlite3)$ { return 444; }
location ~* /(.*)\.(bak|inc|old|7z|zip|rar|xz|tar|gz|tgz|log|bashrc|bash_history|cfg)$ { return 444; }
location ~* /(.*)\.(ini|yml|buildpath|project|settings|mdb|frm|\~|asp|aspx|jsp)$ { return 444; }
# if ( $request_method !~ ^(GET|POST|PUT|DELETE|OPTIONS)$ ) { return 444; }
if ( $query_string ~* ".*['<>].*" ) { return 444; }
if ($request_uri ~* "(cost\()|(concat\()" ) { return 444; }
if ($request_uri ~* "[+|(%20)]union[+|(%20)]" ) { return 444; }
if ($request_uri ~* "[+|(%20)]and[+|(%20)]" ) { return 444; }
if ($request_uri ~* "[+|(%20)]select[+|(%20)]" ) { return 444; }
if ($request_uri ~* "[+|(%20)]or[+|(%20)]" ) { return 444; }
if ($request_uri ~* "[+|(%20)]delete[+|(%20)]" ) { return 444; }
if ($request_uri ~* "[+|(%20)]update[+|(%20)]" ) { return 444; }
if ($request_uri ~* "[+|(%20)]insert[+|(%20)]" ) { return 444; }

if ($query_string ~* ".*('|shell|bash|tmp|--|union|join|sleep|delete|insert|drop|truncate).*") { return 444; }
if ($query_string ~* ".*('|update|grant|exec|where|select|and|count|chr|mid|like|iframe|script).*") { return 444; }
if ($query_string ~* ".*('|alert|webscan|dbappsecurity|style|confirm|innerhtml|innertext|class).*") { return 444; }

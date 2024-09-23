## 保留旧配置的信息

location ~* \.(bak|inc|old|7z|zip|rar|xz|tar|gz|tgz|tar\.gz|log|bashrc|bash_history|cfg|ini|yml|buildpath|project|settings|mdb|frm|\~|asp|aspx|jsp)$ {
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

## 此设置不能修改，导致 某些 java 项目失败 join  union 等关键字
# if ($query_string ~* ".*('|shell|bash|tmp|--|union|join|sleep|delete|insert|drop|truncate|update|grant|exec|where|select|and|count|chr|mid|like|iframe|script|alert|webscan|dbappsecurity|style|confirm|innerhtml|innertext|class).*") {
# if ($query_string ~* ".*('|shell|bash|tmp|--|sleep|delete|insert|drop|truncate|update|grant|exec|where|select|and|count|chr|mid|like|iframe|script|alert|webscan|dbappsecurity|style|confirm|innerhtml|innertext|class).*") {
#     return 445;
# }

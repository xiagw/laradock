location = /favicon.ico {
    access_log off;
    log_not_found off;
}
location ~ /.*favicon.ico {
    access_log off;
    log_not_found off;
}
location = /robots.txt {
    access_log off;
    log_not_found off;
}
location ~ /\.(htaccess|htpasswd|env) {
    deny all;
}
location /.well-known/acme-challenge/ {
    #root /var/www/letsencrypt/;
    log_not_found off;
}
error_page   400 404 /4xx.html;
error_page   500 501 502 503 504  /5xx.html;
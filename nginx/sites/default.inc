location ~* /(.*)(favicon\.ico|robots\.txt) {
    access_log off;
    log_not_found off;
}

location ~* /(.*)\.(htaccess|htpasswd|env) {
    deny all;
}

location /.well-known/acme-challenge/ {
    # root /app/public/letsencrypt/;
    log_not_found off;
}
#error_page   400 404 /4xx.html;
#error_page   500 501 502 503 504  /5xx.html;
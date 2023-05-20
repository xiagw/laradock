## Fixed ThinkPHP deploy subdir
location /tp/ {
    rewrite /tp/(.*)/public/assets/(.*)$ /tp/$1/public/assets/$2 break;
    rewrite /tp/(.*)/public/static/(.*)$ /tp/$1/public/static/$2 break;
    rewrite /tp/(.*)/public/(.*)$ /tp/$1/public/index.php/$2 last;
}
location ~ \.php(.*)$ {
    # try_files $uri uri/ /index.php =404;
    fastcgi_pass 127.0.0.1:9000;
    # fastcgi_pass php-fpm:9000;
    fastcgi_index index.php;
    fastcgi_buffers 16 16k;
    fastcgi_buffer_size 32k;
    ## Fixed ThinkPHP PATH_INFO
    fastcgi_split_path_info ^((?U).+\.php)(/?.+)$;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    fastcgi_param PATH_INFO $fastcgi_path_info;
    fastcgi_param PATH_TRANSLATED $document_root$fastcgi_path_info;
    fastcgi_param APP_ENV product;
    ## fixes timeouts
    fastcgi_read_timeout 600;
    include fastcgi_params;
}

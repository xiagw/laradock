location ~ \.php(.*)$ {
    #fastcgi_pass  unix:/var/run/php-fpm.sock;
    # try_files $uri $uri/ /index.php =404;
    fastcgi_pass php-fpm:9000;
    fastcgi_index index.php;
    fastcgi_buffers 16 16k;
    fastcgi_buffer_size 32k;
    fastcgi_split_path_info ^((?U).+\.php)(/?.+)$;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    fastcgi_param PATH_INFO $fastcgi_path_info;
    fastcgi_param PATH_TRANSLATED $document_root$fastcgi_path_info;
    fastcgi_param APP_ENV product;
    include fastcgi_params;
}

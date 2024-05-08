upstream mayfly-go {
    server mayflygo:8888;
}

server {
    listen       80;
    server_name  mayflygo.net;
    keepalive_requests 120;
    proxy_set_header X-Real_IP $remote_addr;
    proxy_set_header Host $host;
    proxy_set_header X_Forward_For $proxy_add_x_forwarded_for;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection 'upgrade';

    location  / {
        proxy_pass  http://mayfly-go;
    }
}
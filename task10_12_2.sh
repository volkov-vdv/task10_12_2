#!/bin/bash
source $(dirname $(realpath $0))/config

mkdir $(dirname $(realpath $0))/certs
mkdir $(dirname $(realpath $0))/etc

apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 0EBFCD88
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update
apt-get -y install docker-ce docker-compose


openssl req -x509 -newkey rsa:4096 -keyout $(dirname $(realpath $0))/certs/root.key -nodes -out $(dirname $(realpath $0))/certs/root.crt -subj "/CN=VDV/L=Kharkov/C=UA"

openssl rsa -in $(dirname $(realpath $0))/certs/root.key -out $(dirname $(realpath $0))/certs/root.key

openssl genrsa -out $(dirname $(realpath $0))/certs/web.key 4096

openssl req -new -sha256 -key $(dirname $(realpath $0))/certs/web.key -subj "/C=UA/L=Kharkiv/O=Volkov, Inc./CN=$HOST_NAME" -reqexts SAN -config <(cat /etc/ssl/openssl.cnf <(printf "[SAN]\nbasicConstraints=CA:FALSE\nsubjectAltName=DNS:$HOST_NAME,IP:$EXTERNAL_IP")) -out $(dirname $(realpath $0))/certs/web.csr


openssl x509 -req -days 365  -CA $(dirname $(realpath $0))/certs/root.crt -CAkey $(dirname $(realpath $0))/certs/root.key -set_serial 01 -extensions SAN -extfile <(cat /etc/ssl/openssl.cnf <(printf "[SAN]\nbasicConstraints=CA:FALSE\nsubjectAltName=DNS:$HOST_NAME,IP:$EXTERNAL_IP")) -in $(dirname $(realpath $0))/certs/web.csr -out $(dirname $(realpath $0))/certs/web.crt

cat $(dirname $(realpath $0))/certs/root.crt >> $(dirname $(realpath $0))/certs/web.crt

mkdir -p $NGINX_LOG_DIR

cat > $(dirname $(realpath $0))/docker-compose.yml <<EOF
version: '2'

services:
  apache:
    image: $APACHE_IMAGE

  nginx:
    image: $NGINX_IMAGE
    ports:
      - $NGINX_PORT:80
    volumes:
      - ./etc/nginx.conf:/etc/nginx/nginx.conf
      - ./certs:/certs
      - $NGINX_LOG_DIR:/var/log/nginx
    command: bash -c "mkdir -p /certs && nginx -g 'daemon off;'"
    depends_on:
      - apache
EOF

cat > $(dirname $(realpath $0))/etc/nginx.conf <<EOF
worker_processes  1;

events {
    worker_connections  1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    keepalive_timeout  65;

    server {
        listen       80  ssl;
        server_name  localhost;
        ssl_certificate      /certs/web.crt;
        ssl_certificate_key  /certs/web.key;


        location ~ \.(jpg|jpeg|gif|png|ico|css|zip|tgz|gz|rar|bz2|doc|xls|exe|pdf|ppt|txt|tar|mid|midi|wav|bmp|rtf|js)$ {
            root /var/www/html;
        }

        location ~ /\.ht {
            deny  all;
        }

        location / {
            proxy_pass http://apache;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$remote_addr;
            proxy_connect_timeout 120;
            proxy_send_timeout 120;
            proxy_read_timeout 180;
        }
    }
}

EOF

docker-compose -f $(dirname $(realpath $0))/docker-compose.yml up --build -d

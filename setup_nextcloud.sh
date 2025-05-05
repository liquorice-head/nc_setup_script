#!/usr/bin/env bash
set -e

read -rp "Domain (FQDN): " DOMAIN
read -rp "Admin e-mail (Let’s Encrypt): " EMAIL
read -rp "Nextcloud admin user: " NC_ADMIN
read -rsp "Nextcloud admin password: " NC_PASS && echo

apt update
apt install -y ca-certificates curl gnupg lsb-release
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
 https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
>/etc/apt/sources.list.d/docker.list
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

BASE=/opt/nextcloud
mkdir -p "$BASE" && cd "$BASE"

MYSQL_ROOT=$(openssl rand -hex 16)
MYSQL_PASS=$(openssl rand -hex 16)
REDIS_PASS=$(openssl rand -hex 16)

cat >.env <<EOF
MYSQL_ROOT_PASSWORD=$MYSQL_ROOT
MYSQL_DATABASE=nextcloud
MYSQL_USER=nextcloud
MYSQL_PASSWORD=$MYSQL_PASS
REDIS_PASSWORD=$REDIS_PASS
OVERWRITE_HOST=$DOMAIN
EOF

cat >docker-compose.yml <<'YML'
services:
  db:
    image: mariadb:10.9
    restart: always
    environment:
      - MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
      - MYSQL_DATABASE=${MYSQL_DATABASE}
      - MYSQL_USER=${MYSQL_USER}
      - MYSQL_PASSWORD=${MYSQL_PASSWORD}
    volumes:
      - db_data:/var/lib/mysql
  redis:
    image: redis:alpine
    restart: always
    command: ["redis-server","--requirepass","${REDIS_PASSWORD}"]
    volumes:
      - redis_data:/data
  app:
    image: nextcloud:latest
    restart: always
    environment:
      - MYSQL_HOST=db
      - MYSQL_DATABASE=${MYSQL_DATABASE}
      - MYSQL_USER=${MYSQL_USER}
      - MYSQL_PASSWORD=${MYSQL_PASSWORD}
      - REDIS_HOST=redis
      - REDIS_HOST_PASSWORD=${REDIS_PASSWORD}
      - OVERWRITE_HOST=${OVERWRITE_HOST}
      - OVERWRITEPROTOCOL=https
    volumes:
      - nextcloud_data:/var/www/html
    depends_on:
      - db
      - redis
  nginx:
    image: nginx:latest
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./certbot/www:/var/www/certbot
      - /etc/letsencrypt:/etc/letsencrypt
    depends_on:
      - app
volumes:
  db_data:
  redis_data:
  nextcloud_data:
YML

cat >nginx.conf <<EOF
events {}
http {
  server {
    listen 80;
    server_name $DOMAIN;
    root /var/www/certbot;
    location / { return 301 https://\$host\$request_uri; }
    location ~ /.well-known/acme-challenge/ { allow all; root /var/www/certbot; }
  }
  server {
    listen 443 ssl http2;
    server_name $DOMAIN;
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    add_header Strict-Transport-Security "max-age=15552000; includeSubDomains" always;
    location / {
      proxy_pass http://app:80;
      proxy_set_header Host \$host;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto https;
      proxy_connect_timeout 60s;
      proxy_send_timeout 180s;
      proxy_read_timeout 180s;
    }
  }
}
EOF

docker compose pull
docker compose up -d db redis
sleep 20
docker compose up -d app
sleep 40

docker compose exec app php occ maintenance:install \
  --admin-user "$NC_ADMIN" --admin-pass "$NC_PASS" \
  --database "mysql" --database-host "db" \
  --database-name "nextcloud" --database-user "nextcloud" \
  --database-pass "$MYSQL_PASS"

docker compose exec app php occ app:disable firstrunwizard
docker compose exec app bash -c "mkdir -p /var/www/html/custom-skeleton"
docker compose exec app php occ config:system:set skeletondirectory --value "/var/www/html/custom-skeleton"
docker compose exec app php occ config:system:set default_language --value "ru"
docker compose exec app php occ config:system:set maintenance_window_start --value "3"
docker compose exec app php occ config:system:set trusted_proxies 0 --value "172.18.0.0/16"
docker compose exec app php occ db:add-missing-indices
docker compose exec app php occ maintenance:repair --include-expensive

docker compose up -d nginx

docker run --rm -it -v /etc/letsencrypt:/etc/letsencrypt -p 80:80 \
  certbot/certbot certonly --standalone -d $DOMAIN -m $EMAIL --agree-tos --non-interactive

systemctl reload docker

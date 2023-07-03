#!/usr/bin/env bash

## Vars
APP="Nginx Proxy Manager"
YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
BGN=$(echo "\033[4;92m")
GN=$(echo "\033[1;92m")
DGN=$(echo "\033[32m")
CL=$(echo "\033[m")
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"
BFR="\\r\\033[K"
HOLD="-"

## Functions 
catch_errors() {
  set -Eeuo pipefail
  trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
}

msg_info() {
  local msg="$1"
  echo -ne " ${HOLD} ${YW}${msg}..."
}

msg_ok() {
  local msg="$1"
  echo -e "${BFR} ${CM} ${GN}${msg}${CL}"
}

msg_error() {
  local msg="$1"
  echo -e "${BFR} ${CROSS} ${RD}${msg}${CL}"
}

function update {
  if [[ ! -f /lib/systemd/system/npm.service ]]; then
    echo "No ${APP} Installation Found!"
    exit
  fi
  RELEASE=$(curl -s https://api.github.com/repos/NginxProxyManager/nginx-proxy-manager/releases/latest |
    grep "tag_name" |
    awk '{print substr($2, 3, length($2)-4) }')
  msg_info "Stopping Services"
  systemctl stop openresty
  systemctl stop npm
  msg_ok "Stopped Services"

  msg_info "Cleaning Old Files"
  rm -rf /app \
    /var/www/html \
    /etc/nginx \
    /var/log/nginx \
    /var/lib/nginx \
    /var/cache/nginx &>/dev/null
  msg_ok "Cleaned Old Files"

  msg_info "Downloading NPM v${RELEASE}"
  wget -q https://codeload.github.com/NginxProxyManager/nginx-proxy-manager/tar.gz/v${RELEASE} -O - | tar -xz &>/dev/null
  cd nginx-proxy-manager-${RELEASE}
  msg_ok "Downloaded NPM v${RELEASE}"

  msg_info "Setting up Enviroment"
  ln -sf /usr/bin/python3 /usr/bin/python
  ln -sf /usr/bin/certbot /opt/certbot/bin/certbot
  ln -sf /usr/local/openresty/nginx/sbin/nginx /usr/sbin/nginx
  ln -sf /usr/local/openresty/nginx/ /etc/nginx
  sed -i "s+0.0.0+${RELEASE}+g" backend/package.json
  sed -i "s+0.0.0+${RELEASE}+g" frontend/package.json
  sed -i 's+^daemon+#daemon+g' docker/rootfs/etc/nginx/nginx.conf
  NGINX_CONFS=$(find "$(pwd)" -type f -name "*.conf")
  for NGINX_CONF in $NGINX_CONFS; do
    sed -i 's+include conf.d+include /etc/nginx/conf.d+g' "$NGINX_CONF"
  done
  mkdir -p /var/www/html /etc/nginx/logs
  cp -r docker/rootfs/var/www/html/* /var/www/html/
  cp -r docker/rootfs/etc/nginx/* /etc/nginx/
  cp docker/rootfs/etc/letsencrypt.ini /etc/letsencrypt.ini
  cp docker/rootfs/etc/logrotate.d/nginx-proxy-manager /etc/logrotate.d/nginx-proxy-manager
  ln -sf /etc/nginx/nginx.conf /etc/nginx/conf/nginx.conf
  rm -f /etc/nginx/conf.d/dev.conf
  mkdir -p /tmp/nginx/body \
    /run/nginx \
    /data/nginx \
    /data/custom_ssl \
    /data/logs \
    /data/access \
    /data/nginx/default_host \
    /data/nginx/default_www \
    /data/nginx/proxy_host \
    /data/nginx/redirection_host \
    /data/nginx/stream \
    /data/nginx/dead_host \
    /data/nginx/temp \
    /var/lib/nginx/cache/public \
    /var/lib/nginx/cache/private \
    /var/cache/nginx/proxy_temp
  chmod -R 777 /var/cache/nginx
  chown root /tmp/nginx
  echo resolver "$(awk 'BEGIN{ORS=" "} $1=="nameserver" {print ($2 ~ ":")? "["$2"]": $2}' /etc/resolv.conf);" >/etc/nginx/conf.d/include/resolvers.conf
  if [ ! -f /data/nginx/dummycert.pem ] || [ ! -f /data/nginx/dummykey.pem ]; then
    echo -e "${CHECKMARK} \e[1;92m Generating dummy SSL Certificate... \e[0m"
    openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 -subj "/O=Nginx Proxy Manager/OU=Dummy Certificate/CN=localhost" -keyout /data/nginx/dummykey.pem -out /data/nginx/dummycert.pem &>/dev/null
  fi
  mkdir -p /app/global /app/frontend/images
  cp -r backend/* /app
  cp -r global/* /app/global
  wget -q "https://github.com/just-containers/s6-overlay/releases/download/v3.1.5.0/s6-overlay-noarch.tar.xz"
  wget -q "https://github.com/just-containers/s6-overlay/releases/download/v3.1.5.0/s6-overlay-x86_64.tar.xz"
  tar -C / -Jxpf s6-overlay-noarch.tar.xz
  tar -C / -Jxpf s6-overlay-x86_64.tar.xz
  python3 -m pip install --no-cache-dir certbot-dns-cloudflare &>/dev/null
  msg_ok "Setup Enviroment"

  msg_info "Building Frontend"
  cd ./frontend
  export NODE_ENV=development
  yarn install --network-timeout=30000 &>/dev/null
  yarn build &>/dev/null
  cp -r dist/* /app/frontend
  cp -r app-images/* /app/frontend/images
  msg_ok "Built Frontend"

  msg_info "Initializing Backend"
  rm -rf /app/config/default.json &>/dev/null
  if [ ! -f /app/config/production.json ]; then
    cat <<'EOF' >/app/config/production.json
{
  "database": {
    "engine": "knex-native",
    "knex": {
      "client": "sqlite3",
      "connection": {
        "filename": "/data/database.sqlite"
      }
    }
  }
}
EOF
  fi
  cd /app
  export NODE_ENV=development
  yarn install --network-timeout=30000 &>/dev/null
  msg_ok "Initialized Backend"

  msg_info "Starting Services"
  sed -i 's/user npm/user root/g; s/^pid/#pid/g' /usr/local/openresty/nginx/conf/nginx.conf
  sed -i 's/include-system-site-packages = false/include-system-site-packages = true/g' /opt/certbot/pyvenv.cfg
  systemctl enable -q --now openresty
  systemctl enable -q --now npm
  msg_ok "Started Services"

  msg_info "Cleaning up"
  rm -rf ~/nginx-proxy-manager-* s6-overlay-noarch.tar.xz s6-overlay-x86_64.tar.xz
  msg_ok "Cleaned"

  msg_ok "Updated Successfully"
  exit
}

## Execution
catch_errors
update
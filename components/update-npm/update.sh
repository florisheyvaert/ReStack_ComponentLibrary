#!/usr/bin/env bash

# Parameters
VM_CT_ID="$1"          
PROXMOX_HOST="$2"  
USER="$3"
SSH_PRIVATE_KEY="${4:-id_rsa}"

## Vars
messages=()

## Functions
catch_errors() {
  set -Eeuo pipefail
  trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
}

echo_message() {
  local message="$1"
  local error="$2"
  local componentname="update-npm"
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")

  echo '{
      "timestamp": "'"$timestamp"'",
      "componentName": "'"$componentname"'",
      "message": "'"$message"'",
      "error": '$error'
  }'
}

end_script() {
  local status="$1"

  for ((i=0; i<${#messages[@]}; i++)); do
    echo "${messages[i]}"
    echo ","
  done

  exit $status
}

execute_script_on_container() {
  local script_content="$1"

  pct_exec_output=$(ssh -i "$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no root@"$PROXMOX_HOST" "pct exec $VM_CT_ID -- bash -c 'echo \"$script_content\" | bash' 2>&1")

  if echo "$pct_exec_output" | grep -iq "error"; then
      messages+=("$(echo_message "Error in script execution on container. Error: $pct_exec_output" true)")
      end_script 1
  else
      messages+=("$(echo_message "Update script successfully executed on container." false)")
      end_script 0
  fi
}

update() {
  if [[ ! -f /lib/systemd/system/npm.service ]]; then
    messages+=("$(echo_message "No Nginx Proxy Manager Installation Found!" true)")
    end_script 1
  fi

  RELEASE=$(curl -s https://api.github.com/repos/NginxProxyManager/nginx-proxy-manager/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')

  messages+=("$(echo_message "Stopping Services" false)")
  systemctl stop openresty
  systemctl stop npm

  messages+=("$(echo_message "Stopped Services" false)")

  messages+=("$(echo_message "Cleaning Old Files" false)")
  rm -rf /app \
    /var/www/html \
    /etc/nginx \
    /var/log/nginx \
    /var/lib/nginx \
    /var/cache/nginx &>/dev/null

  messages+=("$(echo_message "Cleaned Old Files" false)")

  messages+=("$(echo_message "Downloading NPM v${RELEASE}" false)")
  wget -q https://codeload.github.com/NginxProxyManager/nginx-proxy-manager/tar.gz/v${RELEASE} -O - | tar -xz &>/dev/null
  cd nginx-proxy-manager-${RELEASE}

  messages+=("$(echo_message "Downloaded NPM v${RELEASE}" false)")

  messages+=("$(echo_message "Setting up Environment" false)")
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

  messages+=("$(echo_message "Setup Environment" false)")

  messages+=("$(echo_message "Building Frontend" false)")
  cd ./frontend
  export NODE_ENV=development
  yarn install --network-timeout=30000 &>/dev/null
  yarn build &>/dev/null
  cp -r dist/* /app/frontend
  cp -r app-images/* /app/frontend/images

  messages+=("$(echo_message "Built Frontend" false)")

  messages+=("$(echo_message "Initializing Backend" false)")
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

  messages+=("$(echo_message "Initialized Backend" false)")

  messages+=("$(echo_message "Starting Services" false)")
  sed -i 's/user npm/user root/g; s/^pid/#pid/g' /usr/local/openresty/nginx/conf/nginx.conf
  sed -i 's/include-system-site-packages = false/include-system-site-packages = true/g' /opt/certbot/pyvenv.cfg
  systemctl enable -q --now openresty
  systemctl enable -q --now npm

  messages+=("$(echo_message "Started Services" false)")

  messages+=("$(echo_message "Cleaning up" false)")
  rm -rf ~/nginx-proxy-manager-* s6-overlay-noarch.tar.xz s6-overlay-x86_64.tar.xz

  messages+=("$(echo_message "Cleaned" false)")
  messages+=("$(echo_message "Updated Successfully" false)")

  end_script 0
}

## Run
catch_errors

script_content=$(cat <<EOF
$(declare -f catch_errors)
$(declare -f echo_message)
$(declare -f end_script)
$(declare -f update)
catch_errors
update
EOF
)

execute_script_on_container "$VM_CT_ID" "$script_content"

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
  local componentname="update-uptimekuma"
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

  pct_exec_output=$(ssh -i "$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no "$USER"@"$PROXMOX_HOST" "pct exec $VM_CT_ID -- bash -c 'echo \"$script_content\" | bash' 2>&1")

  if echo "$pct_exec_output" | grep -iq "error"; then
      messages+=("$(echo_message "Error in script execution on container. Error: $pct_exec_output" true)")
      end_script 1
  else
      messages+=("$(echo_message "Update script successfully executed on container." false)")
      end_script 0
  fi
}

update() {
  if [[ ! -d /opt/uptime-kuma ]]; then
    messages+=("$(echo_message "No Kuma Installation Found!" true)")
    end_script 1
  fi

  LATEST=$(curl -sL https://api.github.com/repos/louislam/uptime-kuma/releases/latest | grep '"tag_name":' | cut -d'"' -f4)
  messages+=("$(echo_message "Stopping Kuma" false)")
  sudo systemctl stop uptime-kuma &>/dev/null
  messages+=("$(echo_message "Stopped ${APP}" false)")

  cd /opt/uptime-kuma

  messages+=("$(echo_message "Pulling Kuma ${LATEST}" false)")
  git fetch --all &>/dev/null
  git checkout $LATEST --force &>/dev/null
  messages+=("$(echo_message "Pulled ${LATEST}" false)")

  messages+=("$(echo_message "Updating Kuma to ${LATEST}" false)")
  npm install --production &>/dev/null
  npm run download-dist &>/dev/null
  messages+=("$(echo_message "Updated " false)")

  messages+=("$(echo_message "Starting Kuma" false)")
  sudo systemctl start uptime-kuma &>/dev/null
  messages+=("$(echo_message "Started " false)")
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

#!/bin/bash

# Parameters
KUBE_NODE_LIST=("$1")
KUBE_NODE_IP_LIST=("$2")
KUBECONFIG="$3"
USER="$4"
SSH_PRIVATE_KEY="${5:-id_rsa}"

# Vars
messages=()

# Functions
echo_message() {
  local message="$1"
  local error="$2"
  local componentname="kubernetes-update"
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

drain_node() {
  local node="$1"
  messages+=("$(echo_message "Draining node: $node" false)")
  drain_output=$(KUBECONFIG="$KUBECONFIG" kubectl drain "$node" --ignore-daemonsets --delete-local-data --force --grace-period=60 2>&1)

  if echo "$drain_output" | grep -iq "error"; then
    messages+=("$(echo_message "Failed to drain node: $node" true)")
    messages+=("$(echo_message "$drain_output" true)")
    end_script 1
  else
    messages+=("$(echo_message "Node drained: $node" false)")
  fi
}

uncordon_node() {
  local node="$1"
  messages+=("$(echo_message "Uncordoning node: $node" false)")
  uncordon_output=$(KUBECONFIG="$KUBECONFIG" kubectl uncordon "$node" 2>&1)
  
  if echo "$uncordon_output" | grep -iq "error"; then
    messages+=("$(echo_message "Failed to uncordon node: $node" true)")
    messages+=("$(echo_message "$uncordon_output" true)")
  else
    messages+=("$(echo_message "Node uncordoned: $node" false)")
  fi
}

update_node() {
  local node="$1"
  messages+=("$(echo_message "Updating node: $node" false)")
  update_output=$(ssh -i "$SSH_PRIVATE_KEY" "$USER"@"$node" "dnf update -y" 2>&1)

  if echo "$update_output" | grep -iq "error"; then
      messages+=("$(echo_message "Node update failed. Error: $update_output" true)")
      end_script 1
  else
      messages+=("$(echo_message "Node updated: $node" false)")
      end_script 0
  fi
}

# Run
for i in "${!KUBE_NODE_LIST[@]}"; do
  node="${KUBE_NODE_LIST[$i]}"
  ip="${KUBE_NODE_IP_LIST[$i]}"
  drain_node "$node"
  sleep 10
  update_node "$ip"
  uncordon_node "$node"
  sleep 30
done
messages+=("$(echo_message "All nodes updated!" false)")
end_script 0

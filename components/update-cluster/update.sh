#!/bin/bash

# Parameters
KUBE_NODE_LIST=("node1" "node2" "node3")  # List of Kubernetes nodes
KUBECONFIG="/path/to/kubeconfig"
SSH_PRIVATE_KEY="${3:-id_rsa}"

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
  KUBECONFIG="$KUBECONFIG" kubectl drain "$node" --ignore-daemonsets --delete-local-data --force --grace-period=60 2>&1
  messages+=("$(echo_message "Node drained: $node" false)")
}

uncordon_node() {
  local node="$1"

  messages+=("$(echo_message "Uncordoning node: $node" false)")
  KUBECONFIG="$KUBECONFIG" kubectl uncordon "$node" 2>&1
  messages+=("$(echo_message "Node uncordoned: $node" false)")
}

update_node() {
  local node="$1"

  messages+=("$(echo_message "Updating node: $node" false)")
  ssh -i "$SSH_PRIVATE_KEY" root@"$node" "dnf update -y" 2>&1
  messages+=("$(echo_message "Node updated: $node" false)")
}

# Run
for node in "${KUBE_NODE_LIST[@]}"; do
  drain_node "$node"
  sleep 10  # Wait for node to be drained
  update_node "$node"
  uncordon_node "$node"
  sleep 30  # Wait for some time before moving to the next node
done

end_script 0

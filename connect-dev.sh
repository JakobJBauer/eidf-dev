#!/usr/bin/env bash
# Run this on the EIDF login node after the dev pod is running.
# It copies your SSH keys into the pod and starts port-forward so you can
# connect from your laptop/Cursor with:  ssh eidf-dev
#
# Usage: source connect-dev.sh   OR   ./connect-dev.sh
# Optional: connect-dev.sh [pod-name]   (use specific pod)

set -e

# On EIDF login node, $USER is set (e.g. s2838806-eidf107). Override with EIDF_USER if needed.
EIDF_USER="${EIDF_USER:-$USER}"
PORT="${EIDF_DEV_PORT:-22222}"

get_pod() {
  # Prefer explicit pod name from argv
  if [[ -n "$1" ]]; then
    echo "$1"
    return
  fi
  # List all running dev pods for this user (name contains ${EIDF_USER}-dev-)
  local pods
  pods=$(kubectl get pods -l "eidf/user=${EIDF_USER}" --field-selector=status.phase=Running -o name 2>/dev/null | sed 's|pod/||' | grep -- "-dev-" || true)

  # No pods
  if [[ -z "$pods" ]]; then
    return
  fi

  # Single pod -> just use it
  if [[ "$(echo "$pods" | wc -l)" -eq 1 ]]; then
    echo "$pods"
    return
  fi

  # Multiple pods -> let user pick
  echo "Multiple running dev pods found for user ${EIDF_USER}:"
  # Load into array for stable indexing
  local choice
  local -a pod_list=()
  while IFS= read -r p; do
    [[ -n "$p" ]] && pod_list+=("$p")
  done <<< "$pods"

  local total=${#pod_list[@]}
  local i
  for ((i=0; i<total; i++)); do
    echo "  $((i+1))) ${pod_list[$i]}"
  done

  while true; do
    read -p "Select pod [1-${total}]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 && "$choice" -le ${total} ]]; then
      echo "${pod_list[$((choice-1))]}"
      return
    fi
    echo "Invalid choice. Please enter a number between 1 and ${total}."
  done
}

copy_keys() {
  local pod="$1"
  (sss_ssh_authorizedkeys "$USER" 2>/dev/null; cat ~/.ssh/*.pub 2>/dev/null) | sort -u \
    | kubectl exec -i "$pod" -- bash -c 'mkdir -p /root/.ssh && chmod 700 /root/.ssh && cat > /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys'
  echo "Keys copied to pod $pod"
}

start_port_forward() {
  local pod="$1"
  # Kill any existing port-forward for this port (avoids "address already in use")
  pkill -f "port-forward.*${PORT}:22" 2>/dev/null || true
  sleep 1
  kubectl port-forward "pod/$pod" "${PORT}:22" &
  sleep 2
  disown 2>/dev/null || true
  echo "Port-forward running: localhost:${PORT} -> $pod:22"
}

main() {
  echo "==== EIDF dev pod SSH setup ===="
  echo "User: $EIDF_USER   Port: $PORT"
  echo ""

  POD=$(get_pod "$1")
  if [[ -z "$POD" ]]; then
    echo "No running dev pod found. Create one first:"
    echo "  source ~/eidf-dev/eidf-dev-up.sh   # or from repo: ./eidf-dev-up.sh"
    echo "  kubectl get pods -l eidf/user=$EIDF_USER   # wait until Running"
    return 1
  fi

  echo "Using pod: $POD"
  copy_keys "$POD"
  start_port_forward "$POD"

  echo ""
  echo "==== Ready ===="
  echo "From your laptop (with SSH config from README):"
  echo "  ssh eidf-dev"
  echo "Or in Cursor: Remote-SSH: Connect to Host... -> eidf-dev"
  echo ""
  echo "To stop port-forward later:  pkill -f 'port-forward.*${PORT}:22'"
}

main "$@"

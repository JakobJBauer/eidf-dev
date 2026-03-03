#!/usr/bin/env bash
# One-command setup: run from your laptop to install eidf-dev on the cluster
# and print the SSH config you need for Cursor/ssh eidf-dev.
#
# Usage:
#   ./setup.sh [CLUSTER_SSH_HOST]
#
# Example (if you already have "eidf_cluster" in ~/.ssh/config):
#   cd eidf-dev && ./setup.sh eidf_cluster
#
# This script:
#   1. Syncs this eidf-dev folder to the cluster at ~/eidf-dev/
#   2. Makes scripts executable on the cluster
#   3. Prints the SSH config block to add to ~/.ssh/config (replace CLUSTER_SSH_HOST with your host)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_HOST="${1:-}"

if [[ -z "$CLUSTER_HOST" ]]; then
  echo "EIDF dev – one-command setup"
  echo ""
  echo "This will copy the eidf-dev folder to the cluster and show you the SSH config for 'eidf-dev'."
  echo ""
  read -p "Enter your SSH host alias for the cluster (e.g. eidf_cluster): " CLUSTER_HOST
  [[ -z "$CLUSTER_HOST" ]] && { echo "Need an SSH host."; exit 1; }
fi

echo "Syncing eidf-dev to ${CLUSTER_HOST}:~/eidf-dev/ ..."
if command -v rsync &>/dev/null; then
  rsync -az --delete \
    --exclude='.git' \
    "$SCRIPT_DIR/" "${CLUSTER_HOST}:~/eidf-dev/"
else
  ssh "$CLUSTER_HOST" 'mkdir -p ~/eidf-dev'
  scp -r "$SCRIPT_DIR"/* "${CLUSTER_HOST}:~/eidf-dev/"
fi

echo "Making scripts executable on the cluster..."
ssh "$CLUSTER_HOST" 'chmod +x ~/eidf-dev/*.sh 2>/dev/null || true'

echo ""
echo "==== Setup complete ===="
echo ""
echo "On the cluster, \$USER is set (e.g. s2838806-eidf107). Use:"
echo "  ssh $CLUSTER_HOST"
echo "  source ~/eidf-dev/eidf-dev-up.sh"
echo ""
echo "Add this block to your laptop's ~/.ssh/config:"
echo ""
cat <<SSHBLOCK
Host eidf-dev
    HostName localhost
    Port 22222
    User root
    ProxyJump ${CLUSTER_HOST}
    StrictHostKeyChecking accept-new
    UserKnownHostsFile /dev/null
SSHBLOCK
echo ""
echo "Then from your laptop:  ssh eidf-dev   or in Cursor: Remote-SSH → eidf-dev"
echo ""

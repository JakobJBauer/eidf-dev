#!/usr/bin/env bash
# Create a PVC on the EIDF cluster. Run on the login node.
# Default: local pvc.yml in this repo. Override with EIDF_PVC_TEMPLATE (e.g. /opt/infk8s/templates/pvc.yml).
#
# Usage: bash eidf-create-pvc.sh [PVC_NAME] [STORAGE]
#   With no args: interactive (prompts for name and size).
#   With PVC_NAME and optional STORAGE: create that PVC (prompt for size if STORAGE omitted).

set -e

EIDF_USER="${EIDF_USER:-$USER}"
EIDF_DEV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
# Default to local pvc.yml in this repo; set EIDF_PVC_TEMPLATE to use cluster /opt/infk8s/templates/pvc.yml
EIDF_PVC_TEMPLATE="${EIDF_PVC_TEMPLATE:-$EIDF_DEV_DIR/pvc.yml}"
EIDF_PVC_STORAGE_CLASS="${EIDF_PVC_STORAGE_CLASS:-csi-cephfs-sc}"

echo ""
echo "==== Create a PVC ===="
echo "User: $EIDF_USER"
echo ""

# Optional args: PVC name, then optional size
PVC_NAME="$1"
STORAGE="$2"

# Show existing PVCs (exclude Terminating) and prompt for name/size if not given
ALL_PVCS=$(kubectl get pvc -o go-template='{{range .items}}{{if not .metadata.deletionTimestamp}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}' 2>/dev/null | sort -u)
MY_PVCS=()
while IFS= read -r line; do
  [[ -n "$line" && "$line" == "${EIDF_USER}-"* ]] && MY_PVCS+=("$line")
done <<< "$ALL_PVCS"

if [[ ${#MY_PVCS[@]} -gt 0 ]]; then
  echo "Your existing PVCs: ${MY_PVCS[*]}"
  echo ""
fi

if [[ -z "$PVC_NAME" ]]; then
  read -p "New PVC name? [${EIDF_USER}-ws1] " PVC_NAME
  PVC_NAME="${PVC_NAME:-${EIDF_USER}-ws1}"
fi

if kubectl get pvc "$PVC_NAME" -o name &>/dev/null; then
  echo "PVC $PVC_NAME already exists."
  exit 0
fi

if [[ -z "$STORAGE" ]]; then
  echo "Common sizes: 100Gi, 500Gi, 1Ti, 2.5Ti"
  read -p "Storage size? [100Gi] " STORAGE
  STORAGE="${STORAGE:-100Gi}"
fi

echo ""
echo "Creating PVC: $PVC_NAME ($STORAGE)..."

# Template uses $PVCNAME, $USER, $STORAGE (cluster and local pvc.yml are the same format)
export PVCNAME="$PVC_NAME"
export USER="$EIDF_USER"
export STORAGE

if [[ -f "$EIDF_PVC_TEMPLATE" ]]; then
  envsubst < "$EIDF_PVC_TEMPLATE" | kubectl create -f -
else
  echo "Template not found at $EIDF_PVC_TEMPLATE; using inline PVC (set EIDF_PVC_STORAGE_CLASS if needed, current: $EIDF_PVC_STORAGE_CLASS)."
  cat <<EOF | kubectl create -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${PVC_NAME}
  labels:
    eidf/user: ${EIDF_USER}
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: ${STORAGE}
  storageClassName: ${EIDF_PVC_STORAGE_CLASS}
EOF
fi

echo ""
echo "PVC $PVC_NAME created. Use it in eidf-dev-up.sh or mount it in your jobs."
echo ""

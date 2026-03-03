#!/usr/bin/env bash
# One-command EIDF dev pod: interactive environment (GPU, RAM, PVC), create Job,
# wait for pod, copy keys, port-forward. Then: ssh eidf-dev
#
# Run on the EIDF login node:  source ~/eidf-dev-up.sh   or   ./eidf-dev-up.sh

set -e

# On EIDF login node, $USER is set (e.g. s2838806-eidf107). Override with EIDF_USER if needed.
EIDF_USER="${EIDF_USER:-$USER}"
PORT="${EIDF_DEV_PORT:-22222}"
BASE_NAME="${EIDF_USER}-dev-"
EIDF_QUEUE="${EIDF_QUEUE:-eidf107ns-user-queue}"
EIDF_DEV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"

echo ""
echo "==== EIDF dev pod – create and connect ===="
echo "User: $EIDF_USER   Port: $PORT"
echo ""

# --- GPU count ---
read -p "Number of GPUs? [0] " GPU_COUNT
GPU_COUNT=${GPU_COUNT:-0}
if ! [[ "$GPU_COUNT" =~ ^[0-9]+$ ]]; then
  echo "Invalid GPU count."
  exit 1
fi

# --- RAM ---
if [ "$GPU_COUNT" -eq 0 ]; then
  RAM_GB=16
else
  RAM_GB=$((GPU_COUNT * 50))
  [ "$RAM_GB" -lt 16 ] && RAM_GB=16
fi
read -p "Memory (Gi)? [${RAM_GB}] " RAM_IN
RAM_GB=${RAM_IN:-$RAM_GB}
echo "→ Memory: ${RAM_GB}Gi"

# --- GPU type (if GPU > 0) ---
NODE_SELECTOR=""
if [ "$GPU_COUNT" -gt 0 ]; then
  echo "Select GPU type:"
  echo "  1) NVIDIA H200"
  echo "  2) NVIDIA H100 80GB (HBM3)"
  echo "  3) A100 40GB (default)"
  echo "  4) A100 80GB"
  read -p "Choice [1-4, default 3]: " GPU_CHOICE
  GPU_CHOICE=${GPU_CHOICE:-3}
  case $GPU_CHOICE in
    1) GPU_PRODUCT="NVIDIA-H200" ;;
    2) GPU_PRODUCT="NVIDIA-H100-80GB-HBM3" ;;
    3) GPU_PRODUCT="NVIDIA-A100-SXM4-40GB" ;;
    4) GPU_PRODUCT="NVIDIA-A100-SXM4-80GB" ;;
    *) echo "Invalid choice"; exit 1 ;;
  esac
  echo "→ GPU: $GPU_PRODUCT"
  NODE_SELECTOR="
      nodeSelector:
        nvidia.com/gpu.product: ${GPU_PRODUCT}"
fi

# --- CPUs (min 4; default 2+4*GPUs when GPUs > 0, else 4) ---
if [ "$GPU_COUNT" -gt 0 ]; then
  DEFAULT_CPU=$((2 + 4 * GPU_COUNT))
else
  DEFAULT_CPU=4
fi
[ "$DEFAULT_CPU" -lt 4 ] && DEFAULT_CPU=4
read -p "CPUs? [${DEFAULT_CPU}] " CPU_IN
CPU_COUNT="${CPU_IN:-$DEFAULT_CPU}"
if ! [[ "$CPU_COUNT" =~ ^[0-9]+$ ]]; then
  echo "Invalid CPU count."
  exit 1
fi
[ "$CPU_COUNT" -lt 4 ] && CPU_COUNT=4
echo "→ CPUs: $CPU_COUNT"

# --- PVC: list your PVCs or create a new one ---
ALL_PVCS=$(kubectl get pvc -o go-template='{{range .items}}{{if not .metadata.deletionTimestamp}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}' 2>/dev/null | sort -u)
PVC_LIST=()
while IFS= read -r line; do
  [[ -n "$line" && "$line" == "${EIDF_USER}-"* ]] && PVC_LIST+=("$line")
done <<< "$ALL_PVCS"

echo "Mount a PVC:"
if [[ ${#PVC_LIST[@]} -gt 0 ]]; then
  for i in $(seq 1 ${#PVC_LIST[@]}); do
    echo "  $i) ${PVC_LIST[$((i-1))]}"
  done
fi
echo "  c) Create a new PVC"
echo "  0) No PVC"
DEFAULT_CHOICE="0"
[[ ${#PVC_LIST[@]} -gt 0 ]] && DEFAULT_CHOICE="1"
read -p "Choice [${DEFAULT_CHOICE}]: " PVC_CHOICE
PVC_CHOICE="${PVC_CHOICE:-$DEFAULT_CHOICE}"

PVC_NAME=""
if [[ "$PVC_CHOICE" == "0" || "$PVC_CHOICE" == "n" || "$PVC_CHOICE" == "none" ]]; then
  PVC_NAME=""
elif [[ "$PVC_CHOICE" == "c" || "$PVC_CHOICE" == "C" || "$PVC_CHOICE" == "new" ]]; then
  read -p "New PVC name? [${EIDF_USER}-ws1] " NEW_PVC_NAME
  NEW_PVC_NAME="${NEW_PVC_NAME:-${EIDF_USER}-ws1}"
  echo "Common sizes: 100Gi, 500Gi, 1Ti, 2.5Ti"
  read -p "Storage size? [100Gi] " NEW_PVC_SIZE
  NEW_PVC_SIZE="${NEW_PVC_SIZE:-100Gi}"
  bash "$EIDF_DEV_DIR/eidf-create-pvc.sh" "$NEW_PVC_NAME" "$NEW_PVC_SIZE" || exit 1
  PVC_NAME="$NEW_PVC_NAME"
  echo "→ Using newly created PVC: $PVC_NAME"
elif [[ "$PVC_CHOICE" =~ ^[0-9]+$ ]] && [[ "$PVC_CHOICE" -ge 1 && "$PVC_CHOICE" -le ${#PVC_LIST[@]} ]]; then
  PVC_NAME="${PVC_LIST[$((PVC_CHOICE-1))]}"
  echo "→ PVC: $PVC_NAME"
else
  echo "Invalid choice. Exiting."
  exit 1
fi

if [[ -n "$PVC_NAME" ]]; then
  echo "→ PVC: $PVC_NAME (mount at /workspace, writeable at /workspace/writeable)"
  PVC_VOLUME="
      volumes:
        - name: workspace
          persistentVolumeClaim:
            claimName: ${PVC_NAME}"
  PVC_MOUNT="
          volumeMounts:
            - name: workspace
              mountPath: /workspace"
else
  PVC_VOLUME=""
  PVC_MOUNT=""
fi

# --- Resource block: omit GPU when 0 ---
if [ "$GPU_COUNT" -eq 0 ]; then
  RESOURCES="
          resources:
            limits:
              cpu: ${CPU_COUNT}
              memory: ${RAM_GB}Gi
            requests:
              cpu: ${CPU_COUNT}
              memory: $(( RAM_GB > 2 ? RAM_GB/2 : 1 ))Gi"
else
  RESOURCES="
          resources:
            limits:
              nvidia.com/gpu: ${GPU_COUNT}
              cpu: ${CPU_COUNT}
              memory: ${RAM_GB}Gi
            requests:
              nvidia.com/gpu: ${GPU_COUNT}
              cpu: ${CPU_COUNT}
              memory: $(( RAM_GB > 2 ? RAM_GB/2 : 1 ))Gi"
fi

# --- Build and apply Job ---
echo ""
echo "Creating dev job..."

cat <<EOF | kubectl create -f -
apiVersion: batch/v1
kind: Job
metadata:
  generateName: ${BASE_NAME}
  labels:
    eidf/user: ${EIDF_USER}
    kueue.x-k8s.io/queue-name: ${EIDF_QUEUE}
    kueue.x-k8s.io/priority-class: batch-workload-priority
  annotations:
    eidf/user: $(echo ${EIDF_USER} | sed 's/-eidf107//')
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 86400
  template:
    metadata:
      labels:
        eidf/user: ${EIDF_USER}
    spec:
      activeDeadlineSeconds: 43200
      restartPolicy: Never
      ${NODE_SELECTOR}
      containers:
        - name: dev
          image: ubuntu:22.04
          ports:
            - containerPort: 22
              protocol: TCP
          imagePullPolicy: IfNotPresent
          workingDir: /workspace
          command: ["/bin/bash", "-c"]
          args:
            - |
              set -e
              apt-get update
              apt-get install -y openssh-server rsync nano htop
              mkdir -p /var/run/sshd /root/.ssh /workspace/writeable
              touch /root/.ssh/authorized_keys
              chmod 700 /root/.ssh
              chmod 600 /root/.ssh/authorized_keys
              echo 'cd /workspace/writeable 2>/dev/null || true' >> /root/.bashrc
              sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
              ssh-keygen -A
              /usr/sbin/sshd
              sleep infinity
          ${RESOURCES}
          ${PVC_MOUNT}
      ${PVC_VOLUME}
EOF

# --- Get job name from apply output (we need to re-run to capture it, or use get jobs) ---
sleep 2
JOB_NAME=$(kubectl get jobs -l "eidf/user=${EIDF_USER}" --sort-by=.metadata.creationTimestamp -o name 2>/dev/null \
  | grep "${BASE_NAME}" \
  | tail -n1 \
  | sed 's|job.batch/||')
if [[ -z "$JOB_NAME" ]]; then
  JOB_NAME=$(kubectl get jobs -l "eidf/user=${EIDF_USER}" -o name 2>/dev/null | tail -n1 | sed 's|job.batch/||')
fi

echo "Waiting for pod (job: $JOB_NAME)..."
POD_NAME=""
for i in $(seq 1 120); do
  POD_NAME=$(kubectl get pods -l "job-name=${JOB_NAME}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  [[ -n "$POD_NAME" ]] && break
  sleep 2
done
if [[ -z "$POD_NAME" ]]; then
  echo "No pod found for job $JOB_NAME. Check: kubectl get pods -l job-name=$JOB_NAME"
  exit 1
fi

for i in $(seq 1 120); do
  STATUS=$(kubectl get pod "$POD_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  [[ "$STATUS" == "Running" ]] && break
  sleep 2
done

if [[ "$(kubectl get pod "$POD_NAME" -o jsonpath='{.status.phase}' 2>/dev/null)" != "Running" ]]; then
  echo "Pod did not reach Running. Check: kubectl get pods -l job-name=$JOB_NAME"
  exit 1
fi

echo "Pod ready: $POD_NAME"

# --- Wait for sshd to be listening inside the pod (apt-get install + sshd take a minute) ---
echo "Waiting for SSH to start in pod..."
for i in $(seq 1 90); do
  if kubectl exec "$POD_NAME" -- bash -c 'echo >/dev/tcp/127.0.0.1/22' 2>/dev/null; then
    break
  fi
  sleep 2
done
if ! kubectl exec "$POD_NAME" -- bash -c 'echo >/dev/tcp/127.0.0.1/22' 2>/dev/null; then
  echo "SSH did not start in pod within 3 minutes. Check: kubectl logs $POD_NAME"
  exit 1
fi
echo "SSH ready in pod."

# --- Copy keys ---
(sss_ssh_authorizedkeys "$USER" 2>/dev/null; cat ~/.ssh/*.pub 2>/dev/null) | sort -u \
  | kubectl exec -i "$POD_NAME" -- bash -c 'mkdir -p /root/.ssh && chmod 700 /root/.ssh && cat > /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys'
echo "Keys copied to pod."

# --- Port-forward ---
pkill -f "port-forward.*${PORT}:22" 2>/dev/null || true
sleep 1
kubectl port-forward "pod/$POD_NAME" "${PORT}:22" &
sleep 2
disown 2>/dev/null || true
echo "Port-forward: localhost:${PORT} -> $POD_NAME:22"

echo ""
echo "==== Ready ===="
echo "  ssh eidf-dev"
echo "  Or Cursor: Remote-SSH: Connect to Host... -> eidf-dev"
echo ""
echo "Stop port-forward later:  pkill -f 'port-forward.*${PORT}:22'"
echo ""

# EIDF dev pod – runbook

**One-time:** run `./setup.sh` from your laptop (from inside the `eidf-dev` folder), then add the printed SSH config.  
**Each session:** SSH to the cluster, run `source ~/eidf-dev/eidf-dev-up.sh`, then from the laptop `ssh eidf-dev`.

---

## Step 1 – On your laptop: one-command setup

```bash
cd eidf-dev
bash setup.sh
```

Enter your SSH host alias for the cluster (e.g. `eidf_cluster`) when prompted, or: `bash setup.sh eidf_cluster`. (If you get "Permission denied" with `./setup.sh`, use `bash setup.sh`.)

Add the printed SSH block to your `~/.ssh/config`.

---

## Step 2 – SSH to the cluster

```bash
ssh YOUR_CLUSTER_HOST   # e.g. ssh eidf_cluster
```

(Enter 2FA if prompted.)

---

## Step 3 – On the login node: create pod and connect

```bash
source ~/eidf-dev/eidf-dev-up.sh
```

Answer the prompts:

- **GPUs:** 0 (CPU-only) or 1, 2, …
- **Memory (Gi):** default 16 (0 GPU) or 50×GPUs
- **GPU type** (if GPUs > 0): 1=H200, 2=H100 80GB, 3=A100 40GB, 4=A100 80GB
- **PVC:** choose by number from your existing PVCs, **c** to create a new PVC (then enter name and size), or **0** for no PVC.

The script creates the job, waits for the pod, copies your keys, and starts the port-forward. Workspace is at `/workspace`; `/workspace/writeable` is created if needed.

**If you already have a running dev pod** and only need to (re)connect:

```bash
source ~/eidf-dev/connect-dev.sh
```

---

## Step 4 – On your laptop: connect

- **Cursor:** Remote-SSH: Connect to Host… → **eidf-dev**
- **Terminal:** `ssh eidf-dev`

You land in the dev pod as `root`.

---

## Stop port-forward (on the login node)

```bash
pkill -f 'port-forward.*22222:22'
```

---

## If something fails

- **No running dev pod** – Run `source ~/eidf-dev/eidf-dev-up.sh` and wait until the pod is Running.
- **Connection refused to eidf-dev** – On the login node run `source ~/eidf-dev/connect-dev.sh` again.
- **Permission denied (publickey)** – Run the connect script so your keys are copied into the pod.

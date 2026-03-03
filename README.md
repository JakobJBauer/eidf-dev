# EIDF dev pod – SSH from Cursor in one command

One-command setup to get a **dev pod** on the EIDF GPU cluster (or similar Kubernetes setup) with SSH, so you can use **Cursor** or any IDE over **Remote-SSH** with a single host (`eidf-dev`).

Works for **any user**: the cluster login node sets `$USER` (e.g. `s2838806-eidf107`); scripts use that and infer your PVCs from `kubectl`.

---

## One-command setup (from your laptop)

1. **Clone or download** this `eidf-dev` folder (e.g. from GitHub).

2. **Run the setup script** (it syncs the folder to the cluster and prints the SSH config you need):

   ```bash
   cd eidf-dev
   ./setup.sh
   ```

   When prompted, enter your **SSH host alias** for the cluster (e.g. `eidf_cluster`).  
   Or pass it directly: `./setup.sh eidf_cluster`

3. **Add the printed SSH block** to your laptop’s `~/.ssh/config` (the script fills in your cluster host).

4. **On the cluster**, each time you want a dev session:

   ```bash
   ssh YOUR_CLUSTER_HOST    # e.g. ssh eidf_cluster
   source ~/eidf-dev/eidf-dev-up.sh
   ```

   You’ll be prompted for **GPUs**, **Memory**, **GPU type** (if GPUs > 0), and **PVC** (your PVCs are listed from `kubectl`; default is `$USER-ws1` if it exists). The script creates the job, waits for the pod, copies your SSH keys, and starts the port-forward.

5. **From your laptop**: `ssh eidf-dev` or in Cursor **Remote-SSH: Connect to Host… → eidf-dev**.  
   You land in the pod as `root`. Workspace is at `/workspace`; a **writeable** directory is created at `/workspace/writeable` if the PVC is mounted.

---

## How it works

- **On the cluster**, `$USER` is set (e.g. `s2838806-eidf107`). All scripts use `EIDF_USER="${EIDF_USER:-$USER}"` so they work for any user without editing.
- **PVCs** are inferred with `kubectl get pvc`; you can pick one from the list or type a name. Default is `$USER-ws1` when it exists.
- **Pods** are found by label `eidf/user=$USER`; the connect script prefers pods whose name contains `$USER-dev` (the ones created by `eidf-dev-up.sh`).
- **Port** is 22222 by default; override with `EIDF_DEV_PORT`. Queue is `eidf107ns-user-queue` by default; override with `EIDF_QUEUE`.

---

## Scripts

| Script | Where to run | Purpose |
|--------|----------------|--------|
| **setup.sh** | Laptop | One-time: syncs `eidf-dev/` to cluster, prints SSH config |
| **eidf-dev-up.sh** | Cluster login node | Interactive: create dev job (GPU/RAM/PVC), wait for pod, copy keys, port-forward |
| **connect-dev.sh** | Cluster login node | Connect only: copy keys + port-forward to an existing dev pod |

---

## Reconnect to an existing dev pod

If a dev pod is already running and you only need to (re)connect:

```bash
ssh YOUR_CLUSTER_HOST
source ~/eidf-dev/connect-dev.sh
```

Optional: `source ~/eidf-dev/connect-dev.sh <pod-name>`

Then from your laptop: `ssh eidf-dev`.

---

## Stopping the port-forward

On the **login node**:

```bash
pkill -f 'port-forward.*22222:22'
```

(Or the port in `EIDF_DEV_PORT`.)

---

## Optional overrides

- **Port:** `export EIDF_DEV_PORT=30222` before sourcing the scripts; use the same port in your `Host eidf-dev` SSH config.
- **User:** `export EIDF_USER=your-username` if you need to override `$USER`.
- **Queue:** `export EIDF_QUEUE=your-queue` if your cluster uses a different Kueue queue.

---

## Troubleshooting

- **“No running dev pod found”** – Run `source ~/eidf-dev/eidf-dev-up.sh` and wait until the pod is Running.
- **“Address already in use”** – Another process is using the port. Stop it with the `pkill` above or set `EIDF_DEV_PORT` to another port and update `~/.ssh/config`.
- **Connection refused to eidf-dev** – On the login node run `source ~/eidf-dev/connect-dev.sh` again so the port-forward is active.
- **Permission denied (publickey)** – Ensure you ran the connect script so your keys were copied into the pod.
- **2FA** – The first hop (your cluster host) will still ask for your authenticator; after that, `eidf-dev` uses key-based auth.

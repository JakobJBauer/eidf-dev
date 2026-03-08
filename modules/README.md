# EIDF dev modules

Optional modules sourced by `eidf-dev-up.sh` to keep the main script smaller and features pluggable.

| Module | Purpose |
|--------|--------|
| `tmux-log-to-pvc.sh` | When `LOG_TO_PVC` is set, configures the pod so tmux logs every pane to `/workspace/writeable/data/logs/`. Sets `LOG_TO_PVC_ENV` and `TMUX_LOG_STARTUP` for the Job spec. |

If a module file is missing, the main script skips it and continues without that feature.

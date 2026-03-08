# Tmux log-to-PVC module for eidf-dev-up.sh
# When LOG_TO_PVC is set, sets LOG_TO_PVC_ENV and TMUX_LOG_STARTUP for the pod spec.
# Source this from eidf-dev-up.sh after EIDF_DEV_DIR is set; it expects no other globals.

LOG_TO_PVC_ENV=""
TMUX_LOG_STARTUP=""

if [[ -n "${LOG_TO_PVC:-}" ]]; then
  LOG_TO_PVC_ENV="
          env:
            - name: LOG_TO_PVC
              value: \"1\""

  # Script that runs inside the container: create tmux-hook.sh and append hooks to /root/.tmux.conf
  TMUX_SETUP_SCRIPT='mkdir -p /workspace/writeable/data/logs
cat > /workspace/writeable/data/logs/tmux-hook.sh << '\''HOOKEND'\''
#!/bin/sh
LOG_DIR="/workspace/writeable/data/logs"
SESSION_ID="$1"
SESSION_NAME="$2"
PANE_ID="$3"
mkdir -p "$LOG_DIR"
if [ -z "$PANE_ID" ]; then
  PANE_ID=$(tmux list-panes -t "$SESSION_ID" -s -F '\''#{pane_id}'\'' 2>/dev/null | head -1)
fi
LOG=$(tmux show-options -t "$SESSION_ID" -vq @session_log_file 2>/dev/null)
if [ -z "$LOG" ]; then
  LOG="$LOG_DIR/${SESSION_NAME}-$(date +%Y%m%d_%H%M%S).log"
  tmux set-option -t "$SESSION_ID" @session_log_file "$LOG"
fi
if [ -n "$PANE_ID" ]; then
  tmux pipe-pane -t "$PANE_ID" -o "cat >> $LOG" &
fi
HOOKEND
chmod +x /workspace/writeable/data/logs/tmux-hook.sh
cat >> /root/.tmux.conf << '\''CONFEND'\''
set-hook -g after-new-session '\''run-shell "/workspace/writeable/data/logs/tmux-hook.sh #{session_id} #{session_name} #{pane_id}"'\''
set-hook -g after-new-window '\''run-shell "/workspace/writeable/data/logs/tmux-hook.sh #{session_id} #{session_name} #{pane_id}"'\''
set-hook -g after-split-window '\''run-shell "/workspace/writeable/data/logs/tmux-hook.sh #{session_id} #{session_name} #{pane_id}"'\''
CONFEND'

  TMUX_SETUP_B64=$(echo -n "$TMUX_SETUP_SCRIPT" | base64 -w0)
  TMUX_LOG_STARTUP="
              if [ -n \"\\\$LOG_TO_PVC\" ]; then
                echo \"${TMUX_SETUP_B64}\" | base64 -d | bash
              fi"
fi

#!/usr/bin/env bash
# ============================================================
#  SiTech — laptop setup v3
#  sshd/sudo არ სჭირდება: user-space აგენტი + reverse SSH ტუნელი.
#   • sitech-agent.service  — ბრძანებების შემსრულებელი (127.0.0.1:7681)
#   • sitech-relay.service  — ტუნელი VPS-ისკენ (VPS:2222 → ლეპტოპი:7681)
#
#  გაშვება:
#    curl -fsSL "https://raw.githubusercontent.com/sitechfromgeorgia/sitech-agent-setup/main/setup-laptop-relay.sh?v=3" | bash
# ============================================================
set -euo pipefail

VPS_HOST="84.46.250.149"
VPS_USER="root"
REVERSE_PORT="2222"
AGENT_PORT="7681"
REPO_RAW="https://raw.githubusercontent.com/sitechfromgeorgia/sitech-agent-setup/main"
KEY_DIR="$HOME/.ssh"
RELAY_KEY="$KEY_DIR/sitech_relay"
AGENT_DIR="$HOME/.sitech"
AGENT_PY="$AGENT_DIR/laptop-agent.py"
TOKEN_FILE="$HOME/.sitech_agent_token"
SSH_BIN="$(command -v ssh || echo /usr/bin/ssh)"
PY_BIN="$(command -v python3 || echo /usr/bin/python3)"
AGENT_PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDdHwy3MpqWW4cOvRB8zuhmYcyGYH+A5sjrl2NEWtkja sitech-agent@vps-migration"

echo "=== SiTech laptop setup (v3) ==="
echo "user: $(whoami) | host: $(hostname) | ssh: $SSH_BIN | python: $PY_BIN"
echo

# 1) relay keypair (private key never leaves this machine)
mkdir -p "$KEY_DIR"; chmod 700 "$KEY_DIR"
if [ ! -f "$RELAY_KEY" ]; then
  ssh-keygen -t ed25519 -N '' -C "laptop-$(hostname)-$(whoami)" -f "$RELAY_KEY" -q
  echo "-> generated laptop relay keypair"
else
  echo "-> laptop relay keypair already exists"
fi
chmod 600 "$RELAY_KEY"

# 2) authorize the agent's public key for inbound SSH (kept for later use)
touch "$KEY_DIR/authorized_keys"; chmod 600 "$KEY_DIR/authorized_keys"
grep -qF "sitech-agent@vps-migration" "$KEY_DIR/authorized_keys" || echo "$AGENT_PUBKEY" >> "$KEY_DIR/authorized_keys"

# 3) install the user-space agent
mkdir -p "$AGENT_DIR"
curl -fsSL "$REPO_RAW/laptop-agent.py" -o "$AGENT_PY"
chmod 700 "$AGENT_PY"
if [ ! -f "$TOKEN_FILE" ]; then
  head -c 24 /dev/urandom | base64 | tr -d '/+=' > "$TOKEN_FILE"
  echo "-> generated agent token"
else
  echo "-> agent token already exists"
fi
chmod 600 "$TOKEN_FILE"

mkdir -p "$HOME/.config/systemd/user"
cat > "$HOME/.config/systemd/user/sitech-agent.service" <<EOF
[Unit]
Description=SiTech laptop agent (command executor)
After=network-online.target

[Service]
ExecStart=$PY_BIN $AGENT_PY
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF

# 4) reverse tunnel -> the agent port
cat > "$HOME/.config/systemd/user/sitech-relay.service" <<EOF
[Unit]
Description=SiTech reverse SSH relay to VPS
After=network-online.target

[Service]
ExecStart=$SSH_BIN -N -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=accept-new -i $RELAY_KEY -R ${REVERSE_PORT}:localhost:${AGENT_PORT} ${VPS_USER}@${VPS_HOST}
Restart=always
RestartSec=15

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now sitech-agent.service sitech-relay.service
systemctl --user restart sitech-agent.service sitech-relay.service
loginctl enable-linger "$(whoami)" >/dev/null 2>&1 || true

sleep 4
echo
echo "============================================================"
echo "  ეს ხაზი გაუგზავნე აგენტს Telegram-ში (AGENT TOKEN):"
echo
cat "$TOKEN_FILE"
echo
echo "  laptop user = $(whoami)"
echo "============================================================"
echo
echo "--- agent ---"
systemctl --user --no-pager status sitech-agent.service 2>&1 | head -6 || true
echo "--- relay ---"
systemctl --user --no-pager status sitech-relay.service 2>&1 | head -6 || true

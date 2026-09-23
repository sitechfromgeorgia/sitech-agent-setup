#!/usr/bin/env bash
# ============================================================
#  SiTech — laptop relay setup (reverse SSH tunnel to the VPS)
#  უსაფრთხო დიზაინი: კერძო გასაღები ამ ლეპტოპზე იბადება და აქვე რჩება.
#  გარეთ გადის მხოლოდ PUBLIC key (რომელსაც აგენტი ავტორიზებს VPS-ზე).
#
#  გაშვება:  curl -fsSL https://raw.githubusercontent.com/sitechfromgeorgia/sitech-agent-setup/main/setup-laptop-relay.sh | bash
# ============================================================
set -euo pipefail

VPS_HOST="84.46.250.149"
VPS_USER="root"
REVERSE_PORT="2222"
KEY_DIR="$HOME/.ssh"
RELAY_KEY="$KEY_DIR/sitech_relay"
AGENT_PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDdHwy3MpqWW4cOvRB8zuhmYcyGYH+A5sjrl2NEWtkja sitech-agent@vps-migration"

echo "=== SiTech laptop relay setup ==="
echo "user: $(whoami) | host: $(hostname)"
echo

# 1) autossh
if ! command -v autossh >/dev/null 2>&1; then
  echo "-> installing autossh..."
  if command -v apt-get >/dev/null 2>&1; then sudo apt-get update -qq && sudo apt-get install -y -qq autossh
  elif command -v dnf >/dev/null 2>&1; then sudo dnf install -y autossh
  elif command -v pacman >/dev/null 2>&1; then sudo pacman -S --noconfirm autossh
  else echo "!! please install autossh manually and re-run"; exit 1; fi
fi

# 2) this laptop's own relay keypair (private key never leaves this machine)
mkdir -p "$KEY_DIR"; chmod 700 "$KEY_DIR"
if [ ! -f "$RELAY_KEY" ]; then
  ssh-keygen -t ed25519 -N '' -C "laptop-$(hostname)-$(whoami)" -f "$RELAY_KEY" -q
  echo "-> generated laptop relay keypair"
else
  echo "-> laptop relay keypair already exists"
fi
chmod 600 "$RELAY_KEY"

# 3) let the agent SSH *into* this laptop (public key only)
touch "$KEY_DIR/authorized_keys"; chmod 600 "$KEY_DIR/authorized_keys"
grep -qF "sitech-agent@vps-migration" "$KEY_DIR/authorized_keys" || echo "$AGENT_PUBKEY" >> "$KEY_DIR/authorized_keys"

# 4) systemd user service: keeps the reverse tunnel alive (NAT-friendly, outbound only)
mkdir -p "$HOME/.config/systemd/user"
cat > "$HOME/.config/systemd/user/sitech-relay.service" <<EOF
[Unit]
Description=SiTech reverse SSH relay to VPS
After=network-online.target

[Service]
ExecStart=/usr/bin/autossh -M 0 -N -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=accept-new -i $RELAY_KEY -R ${REVERSE_PORT}:localhost:22 ${VPS_USER}@${VPS_HOST}
Restart=always
RestartSec=15

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now sitech-relay.service
loginctl enable-linger "$(whoami)" 2>/dev/null || sudo loginctl enable-linger "$(whoami)" 2>/dev/null || true

echo
echo "============================================================"
echo "  ეს ორი ხაზი გაუგზავნე აგენტს Telegram-ში (PUBLIC key — უსაფრთხოა):"
echo
cat "$RELAY_KEY.pub"
echo "  laptop user = $(whoami)"
echo "============================================================"
echo
echo "(ტუნელი ავტომატურად ჩაირთვება, როგორც კი აგენტი ამ გასაღებს დაამატებს)"
echo
systemctl --user --no-pager status sitech-relay.service 2>&1 | head -10 || true

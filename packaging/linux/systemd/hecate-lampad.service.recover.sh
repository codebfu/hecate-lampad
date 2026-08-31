#!/bin/bash
# Emergency recovery for hecate-propylaea-style hosts:
# - exit 226/NAMESPACE (ProtectSystem=no must not be paired with ReadWritePaths=)
# - agent.update no-op (missing /etc/sudoers.d/hecate-lampad → elevation.available=false)
# Run as root.
set -euo pipefail

DEST="/usr/lib/systemd/system/hecate-lampad.service"
if [ ! -f "${DEST}" ] && [ -f /lib/systemd/system/hecate-lampad.service ]; then
  DEST="/lib/systemd/system/hecate-lampad.service"
fi

install -d -m 755 "$(dirname "${DEST}")"
cat >"${DEST}" <<'EOF'
[Unit]
Description=Hecate Lampad Agent
Documentation=https://github.com/hecate/hecate-lampad-linux
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=hecate-lampad
Group=hecate-ipc
RuntimeDirectory=hecate-lampad
RuntimeDirectoryMode=0750
RuntimeDirectoryPreserve=yes
ExecStart=/usr/bin/hecate-lampad run --config /etc/hecate-lampad/config.toml
Restart=always
RestartSec=10
ProtectSystem=no
PrivateTmp=yes
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6

[Install]
WantedBy=multi-user.target
EOF

SUDOERS="/etc/sudoers.d/hecate-lampad"
if [ ! -f "${SUDOERS}" ]; then
  echo "Installing missing ${SUDOERS}..."
  install -d -m 755 /etc/sudoers.d
  cat >"${SUDOERS}" <<'EOF'
# Sudoers fragment for hecate-lampad elevated shell.run and agent.update (installed by package).
hecate-lampad ALL=(root) NOPASSWD: ALL
EOF
fi
# sudo ignores fragments not owned by root (mode 0440). Manual `cat >` as non-root breaks updates.
chown root:root "${SUDOERS}"
chmod 440 "${SUDOERS}"
if command -v visudo >/dev/null 2>&1; then
  visudo -c -f "${SUDOERS}"
fi

if id hecate-lampad >/dev/null 2>&1; then
  sudo -u hecate-lampad sudo -n true
  echo "sudo NOPASSWD OK for hecate-lampad"
fi

systemctl daemon-reload
systemctl reset-failed hecate-lampad.service 2>/dev/null || true
systemctl restart hecate-lampad.service
systemctl status hecate-lampad.service --no-pager

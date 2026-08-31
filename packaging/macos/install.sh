#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: sudo ./install.sh" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUDOERS_SRC="${SCRIPT_DIR}/etc/sudoers.d/hecate-lampad"
SERVICE_USER="hecate-lampad"
SERVICE_HOME="/var/lib/hecate-lampad"
CONFIG_DIR="/etc/hecate-lampad"
LOG_OUT="/var/log/hecate-lampad.log"
LOG_ERR="/var/log/hecate-lampad.err"
PLIST="/Library/LaunchDaemons/com.hecate.lampad.plist"
LABEL="system/com.hecate.lampad"

install -d -m 755 \
  /usr/local/bin \
  /Library/LaunchDaemons \
  "${CONFIG_DIR}" \
  "${SERVICE_HOME}" \
  /var/log \
  /usr/local/etc/bash_completion.d \
  /usr/local/share/zsh/site-functions \
  /usr/local/share/fish/vendor_completions.d
install -m 755 "${SCRIPT_DIR}/usr/local/bin/hecate-lampad" /usr/local/bin/hecate-lampad
install -m 644 "${SCRIPT_DIR}/Library/LaunchDaemons/com.hecate.lampad.plist" "${PLIST}"
chown root:wheel "${PLIST}"
chmod 644 "${PLIST}"
if [ -f "${SCRIPT_DIR}/usr/local/etc/bash_completion.d/hecate-lampad" ]; then
  install -m 644 "${SCRIPT_DIR}/usr/local/etc/bash_completion.d/hecate-lampad" /usr/local/etc/bash_completion.d/
fi
if [ -f "${SCRIPT_DIR}/usr/local/share/zsh/site-functions/_hecate-lampad" ]; then
  install -m 644 "${SCRIPT_DIR}/usr/local/share/zsh/site-functions/_hecate-lampad" /usr/local/share/zsh/site-functions/
fi
if [ -f "${SCRIPT_DIR}/usr/local/share/fish/vendor_completions.d/hecate-lampad.fish" ]; then
  install -m 644 "${SCRIPT_DIR}/usr/local/share/fish/vendor_completions.d/hecate-lampad.fish" /usr/local/share/fish/vendor_completions.d/
fi
chmod 750 "${CONFIG_DIR}"

if ! dscl . -read "/Users/${SERVICE_USER}" >/dev/null 2>&1; then
  if ! sysadminctl -addUser "${SERVICE_USER}" -fullName "Hecate Lampad" -password "-" \
    -home "${SERVICE_HOME}"; then
    echo "error: could not create user ${SERVICE_USER}" >&2
    exit 1
  fi
fi

# launchd EX_CONFIG (78) if UserName cannot open StandardOutPath/StandardErrorPath.
touch "${LOG_OUT}" "${LOG_ERR}"
chown "${SERVICE_USER}:wheel" "${LOG_OUT}" "${LOG_ERR}" "${SERVICE_HOME}" "${CONFIG_DIR}"
chmod 644 "${LOG_OUT}" "${LOG_ERR}"

if [ -f "${SUDOERS_SRC}" ]; then
  sh "${SCRIPT_DIR}/install-elevation-policy.sh" "${SUDOERS_SRC}"
else
  echo "Warning: sudoers fragment missing from package; elevated shell.run will not work" >&2
fi

launchctl bootout "${LABEL}" 2>/dev/null || true
launchctl enable "${LABEL}" 2>/dev/null || true
if ! launchctl bootstrap system "${PLIST}"; then
  echo "error: launchctl bootstrap failed for ${LABEL}" >&2
  exit 1
fi
launchctl kickstart -k "${LABEL}" 2>/dev/null || true

echo "Installed hecate-lampad. Run: hecate-lampad enroll --server-url <url>"
echo "The agent service starts automatically and waits for enrollment."

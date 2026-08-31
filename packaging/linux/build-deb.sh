#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"
# shellcheck source=packaging/common/agent-version.sh
source "${ROOT}/packaging/common/agent-version.sh"
resolve_agent_package_version "${ROOT}"

ARCH="amd64"
DIST="${ROOT}/dist"
WORK="$(mktemp -d)"
PKG_ROOT="${WORK}/deb-root"
BINARY="${ROOT}/target/release/hecate-lampad"
SUDOERS_SRC="${ROOT}/packaging/sudoers/hecate-lampad"

trap 'rm -rf "${WORK}"' EXIT

cargo build --release

# Version is taken from Cargo.toml / VERSION env.
rm -rf "${DIST}"/*.deb "${DIST}"/*.sha256
mkdir -p "${PKG_ROOT}/DEBIAN" \
  "${PKG_ROOT}/usr/bin" \
  "${PKG_ROOT}/lib/systemd/system" \
  "${PKG_ROOT}/etc/hecate-lampad" \
  "${PKG_ROOT}/etc/sudoers.d" \
  "${PKG_ROOT}/usr/share/bash-completion/completions" \
  "${PKG_ROOT}/usr/share/zsh/vendor-completions" \
  "${PKG_ROOT}/usr/share/fish/vendor_completions.d"

install -m 755 "${BINARY}" "${PKG_ROOT}/usr/bin/hecate-lampad"
install -m 644 packaging/linux/systemd/hecate-lampad.service "${PKG_ROOT}/lib/systemd/system/"
install -m 440 "${SUDOERS_SRC}" "${PKG_ROOT}/etc/sudoers.d/hecate-lampad"

COMPLETIONS="${WORK}/completions"
bash packaging/stage-completions.sh "${ROOT}/completions" "${COMPLETIONS}"
install -m 644 "${COMPLETIONS}/bash/hecate-lampad" "${PKG_ROOT}/usr/share/bash-completion/completions/"
install -m 644 "${COMPLETIONS}/zsh/_hecate-lampad" "${PKG_ROOT}/usr/share/zsh/vendor-completions/"
install -m 644 "${COMPLETIONS}/fish/hecate-lampad.fish" "${PKG_ROOT}/usr/share/fish/vendor_completions.d/"

cat > "${PKG_ROOT}/DEBIAN/control" <<EOF
Package: hecate-lampad
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: ${ARCH}
Maintainer: Hecate Contributors <hecate@localhost>
Description: Hecate Lampad Agent
 Remote command agent for the Hecate platform.
Depends: systemd, sudo
Recommends: bash-completion, qemu-guest-agent
Suggests: hecate-lampad-desktop
EOF

cat > "${PKG_ROOT}/DEBIAN/conffiles" <<'EOF'
/etc/sudoers.d/hecate-lampad
EOF

cat > "${PKG_ROOT}/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if ! getent group hecate-ipc >/dev/null 2>&1; then
  groupadd --system hecate-ipc 2>/dev/null || true
fi
if ! id hecate-lampad >/dev/null 2>&1; then
  useradd --system --home-dir /var/lib/hecate-lampad --shell /usr/sbin/nologin --gid hecate-ipc hecate-lampad 2>/dev/null || true
fi
usermod -a -G hecate-ipc hecate-lampad 2>/dev/null || true
chmod 750 /etc/hecate-lampad 2>/dev/null || true
if [ -f /etc/hecate-lampad/config.toml ]; then
  chown hecate-lampad:hecate-lampad /etc/hecate-lampad /etc/hecate-lampad/config.toml 2>/dev/null || true
  chmod 640 /etc/hecate-lampad/config.toml 2>/dev/null || true
fi
if [ -f /etc/hecate-lampad/agent.key ]; then
  chown hecate-lampad:hecate-lampad /etc/hecate-lampad/agent.key 2>/dev/null || true
  chmod 600 /etc/hecate-lampad/agent.key 2>/dev/null || true
fi
if [ -f /etc/sudoers.d/hecate-lampad ]; then
  chown root:root /etc/sudoers.d/hecate-lampad 2>/dev/null || true
  chmod 440 /etc/sudoers.d/hecate-lampad 2>/dev/null || true
  if command -v visudo >/dev/null 2>&1; then
    visudo -c -f /etc/sudoers.d/hecate-lampad
  fi
fi
systemctl daemon-reload 2>/dev/null || true
systemctl enable hecate-lampad.service 2>/dev/null || true
systemctl restart hecate-lampad.service 2>/dev/null || systemctl start hecate-lampad.service 2>/dev/null || true
# Start qemu-guest-agent on VMs when the recommended package is present.
# The unit is often static on Ubuntu (no [Install] section), so only start/restart.
if command -v systemd-detect-virt >/dev/null 2>&1 \
  && command -v systemctl >/dev/null 2>&1 \
  && dpkg-query -W -f='${Status}' qemu-guest-agent 2>/dev/null | grep -q 'install ok installed'; then
  virt="$(systemd-detect-virt 2>/dev/null || true)"
  case "${virt}" in
    none|""|docker|lxc|openvz|podman|container|wsl) ;;
    *)
      systemctl restart qemu-guest-agent.service 2>/dev/null \
        || systemctl start qemu-guest-agent.service 2>/dev/null \
        || true
      ;;
  esac
fi
EOF
chmod 755 "${PKG_ROOT}/DEBIAN/postinst"

mkdir -p "${DIST}"
OUTPUT="${DIST}/hecate-lampad_${VERSION}_${ARCH}.deb"
dpkg-deb --build "${PKG_ROOT}" "${OUTPUT}"
sha256sum "${OUTPUT}" > "${OUTPUT}.sha256"
echo "Built ${OUTPUT}"

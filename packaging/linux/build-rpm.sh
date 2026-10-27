#!/usr/bin/env bash
# Copyright (C) 2026 Gaultier HUBERT
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Build an x86_64 RPM for hecate-lampad (Fedora / EL9+ compatible).
# Usage: VERSION=1.2.3 ./build-rpm.sh
# Optional: BINARY=/path/to/hecate-lampad (defaults to target/release/hecate-lampad)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"
# shellcheck source=packaging/common/agent-version.sh
source "${ROOT}/packaging/common/agent-version.sh"
resolve_agent_package_version "${ROOT}"

ARCH="x86_64"
DIST="${ROOT}/dist"
WORK="$(mktemp -d)"
BINARY="${BINARY:-${ROOT}/target/release/hecate-lampad}"
SUDOERS_SRC="${ROOT}/packaging/sudoers/hecate-lampad"
RELEASE="${RPM_RELEASE:-1}"

trap 'rm -rf "${WORK}"' EXIT

if [[ ! -x "${BINARY}" ]]; then
  cargo build --release
  BINARY="${ROOT}/target/release/hecate-lampad"
fi

if ! command -v rpmbuild >/dev/null 2>&1; then
  echo "rpmbuild not found; install the rpm package" >&2
  exit 1
fi

rm -rf "${DIST}"/*.rpm "${DIST}"/*.rpm.sha256
mkdir -p "${DIST}"

RPMBUILD="${WORK}/rpmbuild"
mkdir -p \
  "${RPMBUILD}"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS} \
  "${WORK}/payload/usr/bin" \
  "${WORK}/payload/usr/lib/systemd/system" \
  "${WORK}/payload/etc/hecate-lampad" \
  "${WORK}/payload/etc/sudoers.d" \
  "${WORK}/payload/usr/share/bash-completion/completions" \
  "${WORK}/payload/usr/share/zsh/site-functions" \
  "${WORK}/payload/usr/share/fish/vendor_completions.d"

install -m 755 "${BINARY}" "${WORK}/payload/usr/bin/hecate-lampad"
install -m 644 packaging/linux/systemd/hecate-lampad.service \
  "${WORK}/payload/usr/lib/systemd/system/"
install -m 440 "${SUDOERS_SRC}" "${WORK}/payload/etc/sudoers.d/hecate-lampad"

COMPLETIONS="${WORK}/completions"
bash packaging/stage-completions.sh "${ROOT}/completions" "${COMPLETIONS}"
install -m 644 "${COMPLETIONS}/bash/hecate-lampad" \
  "${WORK}/payload/usr/share/bash-completion/completions/"
install -m 644 "${COMPLETIONS}/zsh/_hecate-lampad" \
  "${WORK}/payload/usr/share/zsh/site-functions/"
install -m 644 "${COMPLETIONS}/fish/hecate-lampad.fish" \
  "${WORK}/payload/usr/share/fish/vendor_completions.d/"

tar -C "${WORK}/payload" -czf "${RPMBUILD}/SOURCES/hecate-lampad-${VERSION}.tar.gz" .

cat >"${RPMBUILD}/SPECS/hecate-lampad.spec" <<EOF
Name:           hecate-lampad
Version:        ${VERSION}
Release:        ${RELEASE}%{?dist}
Summary:        Hecate Lampad Agent
License:        GPL-3.0-or-later
URL:            https://github.com/codebfu/hecate-lampad
Source0:        hecate-lampad-%{version}.tar.gz
BuildArch:      ${ARCH}
Requires:       systemd
Requires:       sudo

%description
Remote command agent for the Hecate platform.

%prep
%setup -c -n hecate-lampad-%{version}

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
cp -a . %{buildroot}/

%files
%attr(755,root,root) /usr/bin/hecate-lampad
%attr(644,root,root) /usr/lib/systemd/system/hecate-lampad.service
%config(noreplace) %attr(440,root,root) /etc/sudoers.d/hecate-lampad
%dir %attr(750,root,root) /etc/hecate-lampad
%attr(644,root,root) /usr/share/bash-completion/completions/hecate-lampad
%attr(644,root,root) /usr/share/zsh/site-functions/_hecate-lampad
%attr(644,root,root) /usr/share/fish/vendor_completions.d/hecate-lampad.fish

%post
if ! getent group hecate-ipc >/dev/null 2>&1; then
  groupadd --system hecate-ipc 2>/dev/null || true
fi
if ! id hecate-lampad >/dev/null 2>&1; then
  useradd --system --home-dir /var/lib/hecate-lampad --shell /sbin/nologin --gid hecate-ipc hecate-lampad 2>/dev/null || true
fi
usermod -a -G hecate-ipc hecate-lampad 2>/dev/null || true
install -d -m 0750 /etc/hecate-lampad 2>/dev/null || true
if id hecate-lampad >/dev/null 2>&1; then
  chown hecate-lampad:hecate-ipc /etc/hecate-lampad 2>/dev/null || true
fi
chmod 750 /etc/hecate-lampad 2>/dev/null || true
if [ -f /etc/hecate-lampad/config.toml ]; then
  chown hecate-lampad:hecate-ipc /etc/hecate-lampad/config.toml 2>/dev/null || true
  chmod 640 /etc/hecate-lampad/config.toml 2>/dev/null || true
fi
if [ -f /etc/hecate-lampad/agent.key ]; then
  chown hecate-lampad:hecate-ipc /etc/hecate-lampad/agent.key 2>/dev/null || true
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
if command -v systemd-detect-virt >/dev/null 2>&1 \\
  && command -v systemctl >/dev/null 2>&1 \\
  && rpm -q qemu-guest-agent >/dev/null 2>&1; then
  virt="\$(systemd-detect-virt 2>/dev/null || true)"
  case "\${virt}" in
    none|""|docker|lxc|openvz|podman|container|wsl) ;;
    *)
      systemctl restart qemu-guest-agent.service 2>/dev/null \\
        || systemctl start qemu-guest-agent.service 2>/dev/null \\
        || true
      ;;
  esac
fi

%preun
if [ "\$1" -eq 0 ]; then
  systemctl disable --now hecate-lampad.service 2>/dev/null || true
fi

%postun
systemctl daemon-reload 2>/dev/null || true

%changelog
* $(date '+%a %b %d %Y') Hecate Contributors <hecate@localhost> - ${VERSION}-${RELEASE}
- Package hecate-lampad ${VERSION}
EOF

rpmbuild \
  --define "_topdir ${RPMBUILD}" \
  --define "_build_id_links none" \
  -bb "${RPMBUILD}/SPECS/hecate-lampad.spec"

BUILT="$(find "${RPMBUILD}/RPMS" -name 'hecate-lampad-*.rpm' | head -n 1)"
if [[ -z "${BUILT}" ]]; then
  echo "rpmbuild produced no package" >&2
  exit 1
fi

# Normalize to a stable CI/publish filename (no %{dist} suffix).
OUTPUT="${DIST}/hecate-lampad-${VERSION}-${RELEASE}.${ARCH}.rpm"
cp -f "${BUILT}" "${OUTPUT}"
sha256sum "${OUTPUT}" > "${OUTPUT}.sha256"
echo "Built ${OUTPUT}"

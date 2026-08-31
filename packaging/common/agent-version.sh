#!/usr/bin/env bash
# Resolve platform package VERSION and export HECATE_AGENT_VERSION for hecate-lampad-core/build.rs.
set -euo pipefail

resolve_agent_package_version() {
  local root="${1:?package root directory}"
  if [ -z "${VERSION:-}" ]; then
    VERSION="$(grep '^version' "${root}/Cargo.toml" | head -1 | sed 's/.*"\(.*\)".*/\1/')"
  fi
  export VERSION
  export HECATE_AGENT_VERSION="${HECATE_AGENT_VERSION:-${VERSION}}"
}

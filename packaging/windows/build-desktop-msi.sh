#!/usr/bin/env bash
set -euo pipefail

# Build hecate-lampad-desktop Windows MSI from the sibling desktop source tree.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DESKTOP_DIR="${ROOT}/../hecate-lampad-desktop"
VERSION="${VERSION:-$(grep '^version' "${ROOT}/Cargo.toml" | head -1 | sed 's/.*"\(.*\)".*/\1/')}"
WIX_VERSION="${VERSION}.0"
TARGET="x86_64-pc-windows-gnu"
DIST="${ROOT}/dist"
WORK="$(mktemp -d)"
STAGING="${WORK}/staging"

trap 'rm -rf "${WORK}"' EXIT

if [ ! -f "${DESKTOP_DIR}/Cargo.toml" ]; then
  echo "Error: hecate-lampad-desktop not found at ${DESKTOP_DIR}" >&2
  exit 1
fi

rustup target add "${TARGET}"
cargo build --release --manifest-path "${DESKTOP_DIR}/Cargo.toml" --target "${TARGET}"

mkdir -p "${STAGING}" "${DIST}"
install -m 755 "${DESKTOP_DIR}/target/${TARGET}/release/hecate-lampad-desktop.exe" \
  "${STAGING}/hecate-lampad-desktop.exe"
# Minimal CA helper: registers the logon task without loading the desktop PE.
x86_64-w64-mingw32-gcc -O2 -s -o "${STAGING}/register-logon-task.exe" \
  "${ROOT}/packaging/windows/register-logon-task.c"
# Task Scheduler requires UTF-16 LE with BOM; keep the git source as UTF-8.
python3 - \
  "${DESKTOP_DIR}/packaging/windows/hecate-lampad-desktop-logon.xml" \
  "${STAGING}/hecate-lampad-desktop-logon.xml" <<'PY'
import sys
from pathlib import Path
src = Path(sys.argv[1]).read_text(encoding="utf-8")
Path(sys.argv[2]).write_bytes(src.encode("utf-16"))
PY
install -m 644 "${DESKTOP_DIR}/README.md" "${STAGING}/README.md"

WXS="${WORK}/hecate-lampad-desktop.wxs"
cat > "${WXS}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
  <Product
    Id="*"
    Name="Hecate Lampad Desktop Helper"
    Language="1033"
    Version="${WIX_VERSION}"
    Manufacturer="Hecate Contributors"
    UpgradeCode="a7c3e1f4-2b8d-4e6a-9c12-5f0d8e3b7a91">
    <Package
      InstallerVersion="500"
      Compressed="yes"
      InstallScope="perMachine"
      Description="User-session GUI helper for Hecate computer-use commands"
      Comments="Hecate Lampad Desktop" />
    <Media Id="1" Cabinet="hecate-lampad-desktop.cab" EmbedCab="yes" />
    <UIRef Id="WixUI_Minimal" />
    <MajorUpgrade
      AllowSameVersionUpgrades="yes"
      DowngradeErrorMessage="A newer version of Hecate Lampad Desktop is already installed." />
    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="ProgramFiles64Folder">
        <Directory Id="INSTALLDIR" Name="hecate-lampad-desktop">
          <Component Id="MainExecutable" Guid="3c8f1a62-7e4b-4d90-b1f6-9a2e5c7d8b43">
            <File Id="HecateLampadDesktopExe" Source="staging/hecate-lampad-desktop.exe" KeyPath="yes" />
          </Component>
          <Component Id="RegisterLogonTaskExe" Guid="c4e8a1b2-9f3d-4c70-a6e1-2b5d8f0c7a14">
            <File Id="RegisterLogonTaskExeFile" Source="staging/register-logon-task.exe" KeyPath="yes" />
          </Component>
          <Component Id="LogonTaskXml" Guid="6b2d9f15-8a3c-4e71-c5d9-1f7e4a8b6c32">
            <File Id="HecateLampadDesktopLogonXml" Source="staging/hecate-lampad-desktop-logon.xml" />
          </Component>
          <Component Id="Readme" Guid="9e4a7c21-5b8f-4d63-a2e7-3c1f6b9d4e82">
            <File Id="HecateLampadDesktopReadme" Source="staging/README.md" />
          </Component>
        </Directory>
      </Directory>
    </Directory>
    <Feature Id="DefaultFeature" Title="Hecate Lampad Desktop" Level="1">
      <ComponentRef Id="MainExecutable" />
      <ComponentRef Id="RegisterLogonTaskExe" />
      <ComponentRef Id="LogonTaskXml" />
      <ComponentRef Id="Readme" />
    </Feature>
    <!--
      Register via a tiny mingw helper that only calls schtasks. Do not invoke
      hecate-lampad-desktop.exe here: PE load failures on older Windows (missing
      Win10+ imports) surface as MSI 1722 even when the packaged files are fine.
      Register must be deferred so it runs after InstallFiles copies the XML.
      Unregister is immediate: wixl may sequence Before=RemoveFiles before InstallInitialize,
      and deferred CAs there raise MSI 2762. StartDesktopHelper is best-effort.
    -->
    <CustomAction
      Id="RegisterDesktopLogonTask"
      FileKey="RegisterLogonTaskExeFile"
      ExeCommand="install"
      Execute="deferred"
      Impersonate="no"
      Return="ignore" />
    <CustomAction
      Id="StartDesktopHelper"
      FileKey="RegisterLogonTaskExeFile"
      ExeCommand="start"
      Execute="deferred"
      Impersonate="no"
      Return="ignore" />
    <!--
      Do not use FileKey here: during broken ARP / maintenance upgrades the file
      is not marked for install and MSI raises 2753 even with Return=ignore.
      Call schtasks directly from System32 instead.
    -->
    <CustomAction
      Id="UnregisterDesktopLogonTask"
      Directory="SystemFolder"
      ExeCommand="schtasks.exe /Delete /TN &quot;Hecate Lampad Desktop&quot; /F"
      Execute="immediate"
      Impersonate="no"
      Return="ignore" />
    <InstallExecuteSequence>
      <!--
        Prefer After=InstallValidate for RemoveExistingProducts. wixl may still
        emit a bad sequence when multiple After=InstallFiles CAs exist; the
        build script patches InstallExecuteSequence with msibuild afterward.
      -->
      <RemoveExistingProducts After="InstallValidate" />
      <Custom Action="RegisterDesktopLogonTask" After="InstallFiles">NOT REMOVE</Custom>
      <Custom Action="StartDesktopHelper" After="RegisterDesktopLogonTask">NOT REMOVE</Custom>
      <Custom Action="UnregisterDesktopLogonTask" After="UnpublishFeatures">REMOVE="ALL"</Custom>
    </InstallExecuteSequence>
  </Product>
</Wix>
EOF

# WixUI_Minimal embeds License.rtf from the wixl working directory.
install -m 644 "${ROOT}/packaging/windows/License.rtf" "${WORK}/License.rtf"

OUTPUT="${DIST}/hecate-lampad-desktop_${VERSION}_windows-amd64.msi"
(
  cd "${WORK}"
  wixl -a x64 --ext ui -o "${OUTPUT}" "hecate-lampad-desktop.wxs"
)
# wixl mis-sequences RemoveExistingProducts when multiple After=InstallFiles
# custom actions exist (MSI error 2613). Pin sequences to the known-good layout.
command -v msibuild >/dev/null 2>&1 || {
  echo "Error: msibuild not found (install msitools)" >&2
  exit 1
}
msibuild "${OUTPUT}" \
  -q "UPDATE \`InstallExecuteSequence\` SET \`Sequence\`=1401 WHERE \`Action\`='RemoveExistingProducts'" \
  -q "UPDATE \`InstallExecuteSequence\` SET \`Sequence\`=1801 WHERE \`Action\`='UnregisterDesktopLogonTask'"
sha256sum "${OUTPUT}" > "${OUTPUT}.sha256"
echo "Built ${OUTPUT}"

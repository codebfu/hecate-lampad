#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"
# shellcheck source=packaging/common/agent-version.sh
source "${ROOT}/packaging/common/agent-version.sh"
resolve_agent_package_version "${ROOT}"

WIX_VERSION="${VERSION}.0"
TARGET="x86_64-pc-windows-gnu"
DIST="${ROOT}/dist"
WORK="$(mktemp -d)"
STAGING="${WORK}/staging"

trap 'rm -rf "${WORK}"' EXIT

rustup target add "${TARGET}"

cargo build --release --target "${TARGET}"

rm -rf "${DIST}"/*.msi "${DIST}"/*.zip "${DIST}"/*.sha256
mkdir -p "${STAGING}" "${DIST}"
install -m 755 "target/${TARGET}/release/hecate-lampad.exe" "${STAGING}/hecate-lampad.exe"
install -m 644 README.md "${STAGING}/README.md"

COMPLETIONS="${WORK}/completions"
bash packaging/stage-completions.sh "${ROOT}/completions" "${COMPLETIONS}"
install -m 644 "${COMPLETIONS}/powershell/hecate-lampad.ps1" "${STAGING}/hecate-lampad.ps1"

WXS="${WORK}/hecate-lampad.wxs"
cat > "${WXS}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
  <Product
    Id="*"
    Name="Hecate Lampad Agent"
    Language="1033"
    Version="${WIX_VERSION}"
    Manufacturer="Hecate Contributors"
    UpgradeCode="c4f8e2a1-9b3d-4f6e-a812-7d5c9e0b1a42">
    <Package
      InstallerVersion="500"
      Compressed="yes"
      InstallScope="perMachine"
      Description="Hecate pull-only agent for remote command execution"
      Comments="Hecate Lampad Windows agent" />
    <Media Id="1" Cabinet="hecate-lampad.cab" EmbedCab="yes" />
    <UIRef Id="WixUI_Minimal" />
    <MajorUpgrade
      AllowSameVersionUpgrades="yes"
      DowngradeErrorMessage="A newer version of Hecate Lampad is already installed." />
    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="ProgramFiles64Folder">
        <Directory Id="INSTALLDIR" Name="hecate-lampad">
          <Component Id="MainExecutable" Guid="8f2d6b41-5c7e-4a91-9f0e-2b6d8c4a1e73">
            <File Id="HecateLampadExe" Source="staging/hecate-lampad.exe" KeyPath="yes" />
            <ServiceInstall
              Id="HecateLampadService"
              Name="hecate-lampad"
              DisplayName="Hecate Lampad Agent"
              Description="Hecate pull-only agent for remote command execution"
              Type="ownProcess"
              Start="auto"
              ErrorControl="normal"
              Account="LocalSystem"
              Arguments="run --config C:\ProgramData\hecate-lampad\config.toml"
              Vital="yes" />
            <ServiceControl
              Id="HecateLampadServiceControl"
              Name="hecate-lampad"
              Start="install"
              Stop="both"
              Remove="uninstall"
              Wait="yes" />
          </Component>
          <Component Id="Readme" Guid="5e3b8f94-2a6c-4d17-9c8b-1f7e6a3d5c42">
            <File Id="HecateLampadReadme" Source="staging/README.md" />
          </Component>
          <Component Id="ShellCompletion" Guid="7d4a1c83-9f2e-4b6a-a5d8-3e7f9b2c4d61">
            <File Id="HecateLampadCompletion" Source="staging/hecate-lampad.ps1" />
          </Component>
        </Directory>
      </Directory>
      <Directory Id="CommonAppDataFolder">
        <Directory Id="HecateLampadDataDir" Name="hecate-lampad">
          <Component Id="DataFolder" Guid="2c8e4f17-9a5b-4d6e-b1c3-8f0a7e4d2b91">
            <CreateFolder />
            <RemoveFolder Id="RemoveHecateLampadDataDir" On="uninstall" />
            <RegistryValue
              Root="HKLM"
              Key="Software\Hecate\Lampad"
              Name="DataFolder"
              Type="string"
              Value="[HecateLampadDataDir]"
              KeyPath="yes" />
          </Component>
        </Directory>
      </Directory>
    </Directory>
    <Feature Id="DefaultFeature" Title="Hecate Lampad" Level="1">
      <ComponentRef Id="MainExecutable" />
      <ComponentRef Id="Readme" />
      <ComponentRef Id="ShellCompletion" />
      <ComponentRef Id="DataFolder" />
    </Feature>
  </Product>
</Wix>
EOF

# WixUI_Minimal embeds License.rtf from the wixl working directory.
install -m 644 packaging/windows/License.rtf "${WORK}/License.rtf"

OUTPUT="${DIST}/hecate-lampad_${VERSION}_windows-amd64.msi"
(
  cd "${WORK}"
  wixl -a x64 --ext ui -o "${OUTPUT}" "hecate-lampad.wxs"
)
sha256sum "${OUTPUT}" > "${OUTPUT}.sha256"
echo "Built ${OUTPUT}"
# Service recovery after self-update is handled by the agent (schedule sc start)
# rather than MSI CustomActions: wixl mis-sequences InstallExecuteSequence when
# multiple Custom elements are present (MSI error 2613), as seen on the desktop MSI.

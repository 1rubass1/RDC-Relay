# RDC Relay

RDC Relay is an independent Windows companion GUI and background Host for
Desktop Commander Remote mode. It is not affiliated with the upstream project.

## Install

Download the installer from [GitHub Releases](https://github.com/1rubass1/RDC-Relay/releases).
RDC Relay 1.6.0 uses an independent background Host and graphical interface.
Setup installs per user and offers Node.js 24 LTS if a supported Node.js,
npm and npx installation is missing. The Windows dependency installer may
request administrator permission. Windows can warn about unsigned software
or prevent its execution under Smart App Control.

For portable use, extract the complete Portable ZIP into a local folder
and open RDC Relay.exe. Do not move the executable away from its supporting
files. Installed copies have Desktop/Start Menu shortcuts and an entry in
Windows Installed apps. Stop Remote and exit RDC Relay before uninstalling.

RDC Relay pins @wonderwhy-er/desktop-commander to 0.2.52. Pairing uses the
official upstream device approval flow; approve only devices you recognize.

## Architecture and updates

1.5.x uses the flat legacy update feed in Source/. Its final architecture
transition is 1.6.0. Full Host releases use a separate installer feed,
Source/full-host-update-manifest.json. FullHost/ contains the selected
runtime and installer sources for the new architecture. The retained
internal storage namespace preserves compatibility with prior local data.

The migration offer and full Host feed must remain inactive until the
corresponding exact public release assets are verified. Do not treat a
source snapshot with an inactive feed as an available automatic update.
# Tunnels

Tunnels is a macOS menu bar app that manages SSH tunnels using the system OpenSSH client. It respects your existing `~/.ssh/config`, opens ControlMaster connections, and lets you start/stop local, remote, and dynamic forwards without re-authenticating each time.

Key capabilities:
- Menu bar control for hosts and tunnels.
- Preferences panes for hosts, logs, and reconnect settings.
- Optional use of forwardings defined in `ssh_config`.
- Auto-reconnect with configurable retries and delay.

## How It Works
Tunnels delegates all SSH behavior to `/usr/bin/ssh` and uses ControlMaster sockets to manage a single master connection per host. The master is started on demand and tunnels are added/removed without reconnecting:

```bash
ssh -MNf <host-alias> \
  -o ControlMaster=yes \
  -o ControlPersist=600 \
  -o ControlPath=<socket-path> \
  -o ExitOnForwardFailure=yes

ssh -S <socket-path> -O forward -L 15432:db.internal:5432 <host-alias>
ssh -S <socket-path> -O cancel  -L 15432:db.internal:5432 <host-alias>
ssh -S <socket-path> -O exit <host-alias>
```

The app never parses `ssh_config` directly; it uses `ssh -G <host-alias>` when inspecting host details. Hosts can optionally honor config-defined forwardings (LocalForward/RemoteForward/DynamicForward), otherwise they are cleared on connect.

## Data & Storage
- Host and tunnel configuration is stored as JSON in `~/Library/Application Support/Tunnels/config.json`.
- Control sockets live under `~/Library/Application Support/Tunnels/control` or `/tmp/tunnels-control` when needed to avoid Unix socket path limits.
- Logs are kept in memory for the current session.

## Security Notes
- No keys or passwords are stored; authentication is handled by OpenSSH and the SSH agent.
- No elevated privileges or bundled crypto libraries are required.
- Target platform is macOS 14+.

## Quick Start
- Build: `swift build`
- Run: `swift run Tunnels`

## Packaging & Notarization
- Open in Xcode: `open Package.swift`
- Set your Team, signing, and a bundle identifier in the project settings.
- Archive via Xcode (Product → Archive) to produce a signed `.app`.
- Notarize and staple with Apple’s notarization workflow.

CLI build (optional):
- Unsigned app: `./scripts/build_app.sh`
- Signed export: `TEAM_ID=YOUR_TEAM_ID ./scripts/build_app.sh`
- Wrapped app from SwiftPM binary: `./scripts/build_app.sh` (uses `BUNDLE_ID`, `VERSION`, `SHORT_VERSION` if set)
- Optional codesign for wrapped app: `CODE_SIGN_IDENTITY="Developer ID Application: Your Name" ./scripts/build_app.sh`

Generate an Xcode app project (optional):
- `./scripts/generate_xcodeproj.sh`
- Custom bundle ID: `BUNDLE_ID=com.yourco.tunnels ./scripts/generate_xcodeproj.sh`
 - If `xcodegen` is missing, the script falls back to `swift package generate-xcodeproj` (CLI product only).

Build the generated Xcode app (optional):
- `./scripts/build_xcode_app.sh`
- Signed build: `TEAM_ID=YOUR_TEAM_ID ./scripts/build_xcode_app.sh`

Info.plist:
- The generated Xcode project uses `Resources/Info.plist` (LSUIElement enabled).

Below is a **concise, implementation-ready design document** you can upload to Codex. It is written to be directly actionable, opinionated, and scoped for **macOS 14+**.

---

# SSH Tunnel Menu Bar App — Design Document

## 1. Overview

A native macOS **menu bar app** that manages SSH tunnels for user-defined hosts while **fully respecting existing `~/.ssh/config`** (keys, agent, `ProxyCommand`, `ProxyJump`, `Match`, etc.).

The app **does not implement SSH itself**. Instead, it delegates all SSH behavior to the system **OpenSSH** client (`/usr/bin/ssh`) and manages connections using **ControlMaster** sockets.
This guarantees 1:1 compatibility with Terminal SSH behavior.

Target platform: **macOS 14+ only**

---

## 2. Goals and Non-Goals

### Goals

* 100% compatibility with `ssh_config`
* Manual definition of additional tunnels (L/R/D)
* Fast tunnel add/remove without reconnecting
* Minimal UI, menu-bar only
* No third-party SSH libraries
* Safe shutdown and status reporting

### Non-Goals

* Replacing OpenSSH
* Custom SSH authentication UI
* Editing `ssh_config`
* Windows/Linux support

---

## 3. Architecture

```
SwiftUI MenuBarExtra
        |
        v
TunnelManager (ObservableObject)
        |
        +-- SSHProcessRunner (Process wrapper)
        |
        +-- ControlSocketManager
        |
        +-- ConfigInspector (ssh -G)
```

---

## 4. Core Technical Strategy

### Use `/usr/bin/ssh` with ControlMaster

Each host profile has **one master connection** to its hostname:

```bash
ssh -MNf <hostname> \
  -o ControlMaster=yes \
  -o ControlPersist=600 \
  -o ControlPath=<socket-path> \
  -o ExitOnForwardFailure=yes
```

Additional tunnels are added/removed dynamically:

```bash
ssh -S <socket-path> -O forward -L 15432:db.internal:5432 <hostname>
ssh -S <socket-path> -O cancel  -L 15432:db.internal:5432 <hostname>
ssh -S <socket-path> -O exit <hostname>
```

**Why this works**

* All SSH semantics come from OpenSSH
* One TCP connection per host
* Tunnels are cheap and instant

---

## 5. Data Model

### HostProfile

```swift
struct HostProfile: Identifiable, Codable {
    let id: UUID
    var alias: String          // display name for the host profile
    var hostname: String       // SSH destination
    var tunnels: [TunnelSpec]
}
```

### TunnelSpec

```swift
enum TunnelType: String, Codable { case local, remote, dynamic }

struct TunnelSpec: Identifiable, Codable {
    let id: UUID
    let type: TunnelType
    let localPort: Int
    let remoteHost: String?
    let remotePort: Int?
    var isActive: Bool
}
```

### Runtime State (not persisted)

```swift
struct HostRuntimeState {
    let controlSocketPath: String
    var isMasterRunning: Bool
}
```

---

## 6. Control Socket Management

### Location

```
~/Library/Application Support/Tunnels/control/
```

### Naming

```
ssh-<sha1(hostAlias)>.sock
```

Avoids path-length issues and collisions.

---

## 7. Process Execution Layer

### Requirements

* Use `Process`
* Capture stdout/stderr
* Synchronous execution (short-lived commands)
* Errors surfaced to UI

### Command Helper (conceptual)

```swift
runSSH(args: [String]) -> ExecResult
```

* executable: `/usr/bin/ssh`
* no shell
* no environment overrides

---

## 8. TunnelManager Responsibilities

* Compute control socket path
* Start master connection if needed
* Add/remove tunnels
* Stop master on app quit
* Periodic status check:

  ```bash
  ssh -S <sock> -O check <host>
  ```

### Master lifecycle rules

* Start on first tunnel activation
* Stop when last tunnel removed or user disconnects
* Auto-restart on failure

---

## 9. Respecting `ssh_config`

### Resolution & Debugging

Use:

```bash
ssh -G <host-alias>
```

Used to:

* Validate host alias
* Show effective user, identity, proxy
* Display in “Details” view

The app **never parses** `ssh_config` itself.

---

## 10. SwiftUI UI Specification

### Menu Layout

```
[ Host Alias ]
  ● Connected / ○ Disconnected
  ├─ Tunnel: 15432 → db:5432 [Start/Stop]
  ├─ Tunnel: 9000 → web:80   [Start/Stop]
  ├─ Add Tunnel…
  ├─ Disconnect Host
────────────────────────
Preferences…
Quit
```

### UI Principles

* No modal windows except Preferences
* All actions idempotent
* Status updated from `TunnelManager`

---

## 11. Persistence

* Store `HostProfile` array as JSON in:

  ```
  ~/Library/Application Support/Tunnels/config.json
  ```
* Runtime state is not persisted

---

## 12. Error Handling

* SSH exit codes ≠ 0 → surfaced to UI
* Common failures:

  * Port already bound
  * Auth failure
  * Unknown host alias
* `ExitOnForwardFailure=yes` ensures clean failure

---

## 13. Security Considerations

* No password storage
* SSH agent and keys handled by OpenSSH
* No elevation required
* No network entitlements needed
* No bundled crypto libraries

---

## 14. Build & Distribution

* SwiftUI App
* Hardened Runtime enabled
* No additional entitlements
* No embedded dylibs
* Notarization safe by default

---

## 15. Future Extensions (Out of Scope)

* iCloud sync of tunnel configs
* Auto-connect on login
* Traffic statistics
* SOCKS proxy UI
* SSH agent integration UI

# Remote Desktop

**Remote Desktop** is a native Apple remote-access platform designed for secure, low-latency Mac ↔ Mac screen sharing, remote input control, clipboard synchronization, and file transfer over local network and Internet connections, with iPhone/iPad support where Apple's platform APIs permit it.

---

## Key Features

- **Apple Native Stack**: Built strictly using Swift, SwiftUI, AppKit, ScreenCaptureKit, VideoToolbox, CryptoKit, Security (Keychain), and Network.framework.
- **Cryptographic Device Identity**: Curve25519 asymmetric key pairs for peer identity and signed challenge-response handshakes stored securely in Apple's Keychain.
- **Local Network Discovery**: Automatic LAN discovery and advertising via Bonjour (`_remotedesktop._tcp`) using `Network.framework` (`NWBrowser` / `NWListener`).
- **Secure Single-Use Pairing**: 6-digit short-lived pairing code authorization for establishing mutual trust between devices.
- **Low-Latency Screen Streaming**: Hardware-accelerated `VideoToolbox` H.264/HEVC encoding and `ScreenCaptureKit` display capture.
- **Remote Input Mapping**: Precise normalized coordinate translation to local display dimensions and `CGEvent` mouse, keyboard, scrolling, modifier key, and drag injection.
- **Clipboard & File Transfer**: End-to-end encrypted clipboard synchronization and chunked file transfer with progress tracking and cancellation.
- **Internet NAT Traversal & Relay Fallback**: Stateless WebSocket signaling client with ICE/STUN/TURN evaluation and direct P2P connection with encrypted relay fallback.
- **Host Mode & Menu Bar**: Background availability, incoming session approval alerts, unattended access configuration, and menu bar status indicator (`NSStatusItem`).

---

## Documentation

- [INSTALL.md](Docs/INSTALL.md) - Installation guide, automated build scripts, DMG installer, and iOS sideloading.
- [ARCHITECTURE.md](Docs/ARCHITECTURE.md) - System architecture, component layers, and data flow.
- [SECURITY.md](Docs/SECURITY.md) - Trust model, threat analysis, end-to-end encryption, and Keychain usage.
- [NETWORKING.md](Docs/NETWORKING.md) - Protocol specification, signaling, NAT traversal, and STUN/TURN fallback.
- [DEVELOPMENT.md](Docs/DEVELOPMENT.md) - Building, testing, and running local signaling servers.

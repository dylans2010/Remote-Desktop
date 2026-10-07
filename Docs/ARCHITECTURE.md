# System Architecture

## Architectural Principles

> **The devices perform the actual remote desktop session. Infrastructure solely facilitates discovery, signaling, NAT traversal, and relay fallback.**

No video frames, keystrokes, mouse events, or clipboard contents are routed through or saved on persistent central servers or databases.

```text
                    INTERNET

        ┌──────────────────────────────┐
        │ Temporary Signaling          │
        │ Rendezvous & Metadata Only   │
        └──────────────┬───────────────┘
                       │
          ┌────────────┴────────────┐
          │                         │
        Mac A                     Mac B
          │                         │
          └══════ Direct P2P ═══════┘
                    │
            End-to-End Session
```

If direct P2P connectivity is prevented by restrictive NATs:

```text
Mac A ═════════► Encrypted Relay (TURN) ═════════► Mac B
```

---

## Component Layers

1. **Core**: `DeviceIdentity`, `KeychainManager`, `Device`, `TrustModel`, `ProtocolEngine`.
2. **Networking**: `BonjourDiscoveryManager`, `PairingManager`, `ConnectionTransport`, `SignalingClient`, `NATTraversalEngine`.
3. **RemoteSession**: `VideoEncoderDecoder`, `ClipboardSyncManager`, `FileTransferManager`, `RemoteSessionManager`.
4. **macOS Subsystem**: `ScreenCaptureEngine`, `RemoteInputEngine`, `PermissionsManager`, `DisplayManager`, `HostModeManager`.
5. **iOS Subsystem**: `iOSBroadcastManager` (ReplayKit).
6. **User Interface**: `DeviceListView`, `PairingModalView`, `SessionViewerView`, `SettingsView`, `ContentView`.

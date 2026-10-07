# Development Guide

## Project Structure

- `Remote Desktop.xcodeproj` - Xcode project file configured with `Remote Desktop-macOS` and `Remote Desktop-iOS` targets.
- `Sources/Shared/Core` - Identity, Keychain, Models, Protocol Engine.
- `Sources/Shared/Networking` - Bonjour, Pairing, Signaling, NAT Traversal.
- `Sources/Shared/RemoteSession` - Video Encoding, Session State, Clipboard, File Transfer.
- `Sources/Shared/macOS` - ScreenCaptureKit, Input Injection, Display Manager, Host Mode.
- `Sources/Shared/iOS` - ReplayKit Broadcast Extension Manager.
- `Sources/Shared/UI` - Native SwiftUI views.
- `Sources/Shared/Tests` - Unit & Integration test suite.

## Running Local Signaling Server

A standalone Node.js reference signaling server is included at `Sources/Shared/Networking/signaling_server.js`.

To start local signaling server:
```bash
node "Remote Desktop/Sources/Shared/Networking/signaling_server.js"
```
Server will start listening on port 8080.

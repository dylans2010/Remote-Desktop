# Networking Specification

## Transport Strategy

Remote Desktop prioritizes connection modes in order:
1. **Local LAN**: Direct TCP/IP connection via Bonjour discovery.
2. **Direct P2P**: Direct UDP/ICE candidate connection across local or internet networks.
3. **TURN Relay Fallback**: Encrypted relay proxy transport if direct P2P connection fails due to symmetric NAT.

## Protocol Message Framing

Network messages are encoded using `ProtocolEngine` with version header (`version = 1`). Incompatible versions are rejected during negotiation.

### Message Types
- `hello`: Handshake initiation
- `pairRequest` / `pairAccepted` / `pairRejected`: Single-use pairing flow
- `sessionOffer` / `sessionAnswer` / `iceCandidate`: Internet signaling metadata
- `inputEvent`: Remote mouse, keyboard, scroll, modifier key, drag injection
- `clipboardSync`: Synchronized pasteboard text and data
- `fileOffer` / `fileAccept` / `fileChunk`: Chunked file transfer
- `ping` / `pong`: Heartbeat and latency round-trip time tracking

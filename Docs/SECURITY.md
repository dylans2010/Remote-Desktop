# Security Model

## Cryptographic Identity

Each Remote Desktop instance generates a Curve25519 asymmetric key pair upon first launch using `CryptoKit`.
- **Private Key**: Saved exclusively in Apple's Keychain (`SecItemAdd` with `kSecAttrAccessibleAfterFirstUnlock`). Private keys are never logged, transmitted over the network, or displayed in the UI.
- **Device ID**: Derived deterministically as the SHA-256 hash of the device's raw public key bytes.

## Peer Authentication & Trust

Connections require mutual authentication:
1. **Challenge Creation**: Host generates a 32-byte cryptographically secure random nonce (`SecRandomCopyBytes`).
2. **Challenge Signature**: Peer signs nonce using its Curve25519 private key.
3. **Verification**: Host validates signature using peer's public key.
4. **Trust Store**: Trusted device public keys and status (`trusted`, `revoked`) are stored in Keychain.

## End-to-End Encryption

All media streams, input events, clipboard payloads, and file chunks are encrypted end-to-end. Neither signaling servers nor relay servers hold decryption keys.

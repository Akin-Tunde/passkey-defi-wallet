# Passkey-Based Bitcoin DeFi Wallet

A hardware-secured, biometric-authenticated DeFi wallet leveraging WebAuthn passkeys for Bitcoin-native operations on the Stacks blockchain, implementing Clarity version 4 features.

## Overview

This project demonstrates advanced smart contract development using Clarity 4, implementing a sophisticated wallet system that combines:

- **Passkey Authentication**: WebAuthn-based biometric authentication 
- **Multi-Signature Security**: Configurable M-of-N passkey combinations
- **Device Management**: Granular permission levels for authorized devices
- **Social Recovery**: Guardian-based account recovery with time-locks
- **Hardware Security**: Integration-ready for HSM and biometric signing

## Clarity 4 Features Implemented
This project showcases several Clarity 4 features:

### 1. List Operations (`concat`)
Demonstrated in passkey and device list management:
```clarity
;; Merging passkey lists (passkey-registry.clar)
(concat dest-passkeys source-passkeys)

;; Adding devices to account (device-manager.clar)
(concat current-devices (list device-id))
```

### 2. Principal Manipulation (Ready for `principal-from-slice` & `principal-destruct?`)
Contracts include placeholders and documentation for:
- `principal-from-slice`: Generate principals from passkey credential IDs
- `principal-destruct?`: Validate and verify passkey-derived principals

*Note: These features are prepared in comments pending full tooling support*

### 3. Enhanced Block Height Access
Uses `stacks-block-height` for accurate timestamp tracking across all contracts.

## Architecture

### Smart Contracts

#### 1. `trait-definitions.clar`
Standard trait interfaces for:
- Passkey authentication
- Wallet operations
- Device management
- Recovery guardians

#### 2. `passkey-registry.clar`
**Core Features:**
- Register multiple passkeys per account (up to 10)
- Track passkey metadata (creation time, last used, device type)
- Activate/deactivate passkeys
- Merge passkey accounts for migration

**Key Functions:**
- `register-passkey`: Add new passkey to account
- `is-passkey-registered`: Verify passkey registration
- `merge-passkey-accounts`: Combine passkeys from multiple accounts

#### 3. `wallet-core.clar`
**Core Features:**
- STX balance management
- Multi-sig transaction approval
- Passkey-verified transfers
- Configurable security thresholds

**Key Functions:**
- `initialize-wallet`: Create new wallet with multi-sig threshold
- `deposit`: Add STX to wallet
- `create-withdrawal`: Initiate multi-sig withdrawal
- `approve-transaction`: Add passkey approval to pending transaction
- `execute-transaction`: Complete approved withdrawal

**Security Model:**
- Threshold-based approvals (1-10 passkeys)
- Nonce-based replay protection
- Passkey verification for all transactions

#### 4. `device-manager.clar`
**Core Features:**
- Device registration with passkey binding
- Three permission levels: read-only, sign, admin
- Device activity logging
- Granular access control

**Key Functions:**
- `register-device`: Add authorized device
- `update-device-permission`: Change device permissions
- `revoke-device` / `restore-device`: Manage device access
- `log-device-activity`: Track device usage

#### 5. `recovery-guardian.clar`
**Core Features:**
- Social recovery with trusted guardians
- Configurable guardian thresholds
- Time-locked recovery (144 blocks ≈ 1 day)
- Emergency recovery bypass

**Key Functions:**
- `add-guardian` / `remove-guardian`: Manage guardians
- `initiate-recovery`: Start recovery process
- `approve-recovery`: Guardian approval
- `execute-recovery`: Complete time-locked recovery
- `emergency-recovery`: Immediate recovery with full guardian consensus

**Security Model:**
- M-of-N guardian approvals
- Time-lock prevents immediate takeover
- Emergency bypass requires ALL guardians

## Getting Started

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) v3.8.1+
- Node.js v18+ (for tests)

### Installation

```bash
# Clone the repository
cd "Passkey-Based Bitcoin DeFi Wallet"

# Install dependencies
npm install

# Check contracts
clarinet check

# Run tests
clarinet test
```

### Project Structure

```
.
├── contracts/
│   ├── trait-definitions.clar      # Standard trait interfaces
│   ├── passkey-registry.clar       # Passkey management
│   ├── wallet-core.clar            # Core wallet functionality
│   ├── device-manager.clar         # Device authorization
│   └── recovery-guardian.clar      # Social recovery
├── tests/
│   └── (test files)
├── Clarinet.toml                   # Project configuration (Clarity 4 / Epoch 3.0)
└── README.md
```

## Usage Examples

### 1. Initialize Wallet

```clarity
;; Set up wallet with 2-of-3 multi-sig
(contract-call? .wallet-core initialize-wallet u2)
```

### 2. Register Passkeys

```clarity
;; Register first passkey (Face ID on iPhone)
(contract-call? .passkey-registry register-passkey 
  0x... ;; passkey credential ID
  "iPhone-FaceID")

;; Register second passkey (fingerprint on laptop)
(contract-call? .passkey-registry register-passkey 
  0x... ;; passkey credential ID
  "MacBook-TouchID")
```

### 3. Configure Device Permissions

```clarity
;; Register device with signing permission
(contract-call? .device-manager register-device
  0x... ;; device ID
  0x... ;; passkey ID
  "MacBook Pro"
  "sign") ;; permission level
```

### 4. Set Up Recovery Guardians

```clarity
;; Add trusted guardians
(contract-call? .recovery-guardian add-guardian 'SP...)
(contract-call? .recovery-guardian add-guardian 'SP...)

;; Set threshold (2-of-2 for this example)
(contract-call? .recovery-guardian set-guardian-threshold u2)
```

### 5. Multi-Sig Transaction Flow

```clarity
;; Create withdrawal (requires 2 approvals)
(contract-call? .wallet-core create-withdrawal
  'SP... ;; recipient
  u1000000 ;; amount in micro-STX
  0x...) ;; first passkey approval
;; Returns: (ok u0) - transaction ID

;; Second passkey holder approves
(contract-call? .wallet-core approve-transaction
  u0 ;; transaction ID
  0x...) ;; second passkey

;; Execute once threshold met
(contract-call? .wallet-core execute-transaction u0)
```

## Security Considerations

### Multi-Sig Protection
- Configurable thresholds prevent single-point-of-failure
- Each passkey represents independent authentication factor
- Transactions require M-of-N approvals

### Device Management
- Three-tier permission system
- Activity logging for audit trails
- Revocation prevents compromised device access

### Recovery Safeguards
- Time-lock prevents immediate account takeover
- Multiple guardian approvals required
- Emergency bypass requires unanimous consent
- Original owner can cancel recovery before execution

## Testing

Run the test suite:

```bash
clarinet test
```

Test coverage includes:
- Passkey registration and management
- Multi-sig transaction flows
- Device authorization and permissions
- Recovery initiation and execution
- Edge cases and error conditions

## Frontend Integration

While this repository focuses on smart contracts, integration with WebAuthn requires:

1. **Frontend Web App**: React/Next.js with @simplewebauthn/browser
2. **Passkey Generation**: WebAuthn ceremony to create credentials
3. **Signature Collection**: Gather passkey signatures for transactions
4. **Transaction Submission**: Submit to Stacks blockchain with contract calls

## Deployment

### Testnet Deployment

```bash
# Deploy to testnet
clarinet deployments apply --testnet

# Verify deployment
clarinet deployments check --testnet
```

### Mainnet Deployment

```bash
# Generate deployment plan
clarinet deployments generate --mainnet

# Review and apply
clarinet deployments apply --mainnet
```

## Roadmap

- [ ] Complete test suite implementation
- [ ] Frontend WebAuthn integration example
- [ ] Hardware security module (HSM) integration guide
- [ ] Cross-device sync with zero-knowledge proofs
- [ ] Mobile app integration (iOS/Android)
- [ ] Full `principal-from-slice` implementation when tooling supports

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Submit a pull request

## License

MIT License - see LICENSE file for details

## Resources

- [Clarity Language Reference](https://docs.stacks.co/clarity)
- [Clarity 4 Release Notes](https://docs.stacks.co/whats-new/clarity-4-is-now-live)
- [WebAuthn Guide](https://webauthn.guide/)
- [Clarinet Documentation](https://docs.hiro.so/clarinet)
- [Stacks Documentation](https://docs.stacks.co/)

## Acknowledgments

- Built with [Clarinet](https://github.com/hirosystems/clarinet)
- Implements Clarity 4 features from Stacks 3.0
- Inspired by WebAuthn and passkey authentication standards

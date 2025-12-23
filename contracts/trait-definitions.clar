;; Trait Definitions for Passkey-Based Bitcoin DeFi Wallet
;; Defines standard interfaces for wallet operations and passkey verification

;; Passkey Authenticator Trait
;; Contracts implementing this trait can verify passkey-based authentication
(define-trait passkey-authenticator
  (
    ;; Verify a passkey credential
    (verify-passkey (principal (buff 65)) (response bool uint))
    
    ;; Check if a passkey is registered for a principal
    (is-passkey-registered (principal (buff 65)) (response bool uint))
  )
)

;; Wallet Operations Trait
;; Core wallet functionality interface
(define-trait wallet-operations
  (
    ;; Transfer STX from wallet
    (transfer (uint principal (buff 65)) (response bool uint))
    
    ;; Get wallet balance
    (get-balance (principal) (response uint uint))
    
    ;; Multi-sig configuration
    (set-multisig-threshold (uint) (response bool uint))
  )
)

;; Device Manager Trait
;; Device authorization and management
(define-trait device-manager-trait
  (
    ;; Authorize a new device
    (authorize-device ((buff 65) (buff 65) (string-ascii 50) (string-ascii 20)) (response bool uint))
    
    ;; Revoke device access
    (revoke-device ((buff 65)) (response bool uint))
    
    ;; Check device authorization
    (is-device-authorized (principal (buff 65)) (response bool uint))
  )
)

;; Recovery Guardian Trait
;; Social recovery functionality
(define-trait recovery-guardian-trait
  (
    ;; Add a guardian
    (add-guardian (principal) (response bool uint))
    
    ;; Remove a guardian
    (remove-guardian (principal) (response bool uint))
    
    ;; Approve recovery
    (approve-recovery (principal) (response bool uint))
  )
)


;; Standard interfaces for the Passkey Wallet Ecosystem
(define-trait wallet-core-trait
  (
    (initialize-wallet (uint) (response bool uint))
    (deposit (uint) (response bool uint))
    (create-withdrawal (principal uint (buff 65)) (response uint uint))
    (execute-transaction (uint) (response bool uint))
  )
)

(define-trait registry-trait
  (
    (register-passkey ((buff 65) (string-ascii 50)) (response bool uint))
    (is-passkey-registered (principal (buff 65)) (response bool uint))
  )
)
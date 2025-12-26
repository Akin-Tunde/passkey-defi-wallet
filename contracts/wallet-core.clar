;; Wallet Core Contract - Improved
(use-trait registry-trait .trait-definitions.registry-trait)

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant TREASURY 'STNHKEPYEPJ8ET55ZZ0M5A34J0R3N5FM2CMMMAZ6)
(define-constant REGISTRATION-FEE u1000000) ;; 1 STX
(define-constant TRANSACTION-FEE u50000)    ;; 0.05 STX

(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-INSUFFICIENT-BALANCE (err u201))
(define-constant ERR-WALLET-NOT-FOUND (err u203))
(define-constant ERR-PASSKEY-NOT-VERIFIED (err u204))
(define-constant ERR-MULTISIG-THRESHOLD-NOT-MET (err u205))
(define-constant ERR-DUPLICATE-APPROVAL (err u208))

;; Data structures
(define-map wallets
  { owner: principal }
  {
    balance: uint,
    nonce: uint,
    multisig-threshold: uint,
    created-at: uint
  }
)

(define-map pending-transactions
  { tx-id: uint }
  {
    from: principal,
    to: principal,
    amount: uint,
    approvals: (list 10 (buff 65)),
    executed: bool
  }
)

(define-data-var next-tx-id uint u0)

;; Read-only functions
(define-read-only (get-balance (owner principal))
  (default-to u0 (get balance (map-get? wallets { owner: owner })))
)

(define-read-only (has-enough-approvals (tx-id uint))
  (match (map-get? pending-transactions { tx-id: tx-id })
    tx-data (let (
        (wallet-info (unwrap! (map-get? wallets { owner: (get from tx-data) }) false))
        (threshold (get multisig-threshold wallet-info))
      )
      (>= (len (get approvals tx-data)) threshold))
    false
  )
)

;; Public functions
(define-public (initialize-wallet (initial-threshold uint))
  (let ((owner tx-sender))
    (asserts! (is-none (map-get? wallets { owner: owner })) ERR-NOT-AUTHORIZED)
    (asserts! (and (>= initial-threshold u1) (<= initial-threshold u10)) (err u206))
    
    ;; Pay registration fee
    (try! (stx-transfer? REGISTRATION-FEE tx-sender TREASURY))

    (map-set wallets { owner: owner } {
      balance: u0,
      nonce: u0,
      multisig-threshold: initial-threshold,
      created-at: stacks-block-height
    })
    (ok true)
  )
)

(define-public (create-withdrawal (to principal) (amount uint) (passkey-id (buff 65)))
  (let (
      (owner tx-sender)
      (wallet-data (unwrap! (map-get? wallets { owner: owner }) ERR-WALLET-NOT-FOUND))
      (tx-id (var-get next-tx-id))
    )
    ;; Check balance + fee
    (asserts! (>= (get balance wallet-data) (+ amount TRANSACTION-FEE)) ERR-INSUFFICIENT-BALANCE)
    
    ;; Verify passkey is registered
    (asserts! (contract-call? .passkey-registry is-passkey-registered owner passkey-id) ERR-PASSKEY-NOT-VERIFIED)

    (map-set pending-transactions { tx-id: tx-id } {
      from: owner,
      to: to,
      amount: amount,
      approvals: (list passkey-id),
      executed: false
    })

    (var-set next-tx-id (+ tx-id u1))
    (try! (contract-call? .passkey-registry update-passkey-usage passkey-id))
    (ok tx-id)
  )
)

(define-public (approve-transaction (tx-id uint) (passkey-id (buff 65)))
  (let (
      (tx-data (unwrap! (map-get? pending-transactions { tx-id: tx-id }) ERR-WALLET-NOT-FOUND))
      (current-approvals (get approvals tx-data))
    )
    (asserts! (not (get executed tx-data)) ERR-NOT-AUTHORIZED)
    (asserts! (contract-call? .passkey-registry is-passkey-registered (get from tx-data) passkey-id) ERR-PASSKEY-NOT-VERIFIED)
    
    ;; Prevent duplicate approvals from same passkey
    (asserts! (is-none (index-of current-approvals passkey-id)) ERR-DUPLICATE-APPROVAL)

    (map-set pending-transactions { tx-id: tx-id }
      (merge tx-data {
        approvals: (unwrap-panic (as-max-len? (concat current-approvals (list passkey-id)) u10))
      })
    )
    (ok true)
  )
)

(define-public (execute-transaction (tx-id uint))
  (let (
      (tx-data (unwrap! (map-get? pending-transactions { tx-id: tx-id }) ERR-WALLET-NOT-FOUND))
      (owner (get from tx-data))
      (wallet-data (unwrap! (map-get? wallets { owner: owner }) ERR-WALLET-NOT-FOUND))
    )
    (asserts! (has-enough-approvals tx-id) ERR-MULTISIG-THRESHOLD-NOT-MET)
    (asserts! (not (get executed tx-data)) ERR-NOT-AUTHORIZED)

    ;; Execute transfers
    (try! (as-contract (stx-transfer? TRANSACTION-FEE (as-contract tx-sender) TREASURY)))
    (try! (as-contract (stx-transfer? (get amount tx-data) (as-contract tx-sender) (get to tx-data))))

    ;; Update State
    (map-set wallets { owner: owner }
      (merge wallet-data { 
        balance: (- (get balance wallet-data) (+ (get amount tx-data) TRANSACTION-FEE)),
        nonce: (+ (get nonce wallet-data) u1)
      })
    )
    (map-set pending-transactions { tx-id: tx-id } (merge tx-data { executed: true }))
    (ok true)
  )
)

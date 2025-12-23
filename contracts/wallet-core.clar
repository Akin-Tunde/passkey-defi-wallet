;; Wallet Core Contract
;; Core wallet functionality with passkey-based authentication
;; Features: principal-from-slice, list-filter-map for multi-sig operations

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-INSUFFICIENT-BALANCE (err u201))
(define-constant ERR-INVALID-AMOUNT (err u202))
(define-constant ERR-WALLET-NOT-FOUND (err u203))
(define-constant ERR-PASSKEY-NOT-VERIFIED (err u204))
(define-constant ERR-MULTISIG-THRESHOLD-NOT-MET (err u205))
(define-constant ERR-INVALID-THRESHOLD (err u206))
(define-constant ERR-NONCE-MISMATCH (err u207))

;; Data structures
(define-map wallets
  { owner: principal }
  {
    balance: uint,
    nonce: uint,
    multisig-threshold: uint,
    total-passkeys: uint,
    created-at: uint,
  }
)

(define-map pending-transactions
  { tx-id: uint }
  {
    from: principal,
    to: principal,
    amount: uint,
    approvals: (list 10 (buff 65)),
    approval-count: uint,
    created-at: uint,
    executed: bool,
  }
)

(define-data-var next-tx-id uint u0)

;; Read-only functions

;; Get wallet info
(define-read-only (get-wallet-info (owner principal))
  (map-get? wallets { owner: owner })
)

;; Get wallet balance
(define-read-only (get-balance (owner principal))
  (ok (get balance
    (default-to {
      balance: u0,
      nonce: u0,
      multisig-threshold: u1,
      total-passkeys: u0,
      created-at: u0,
    }
      (map-get? wallets { owner: owner })
    )))
)

;; Get pending transaction
(define-read-only (get-pending-transaction (tx-id uint))
  (map-get? pending-transactions { tx-id: tx-id })
)

;; Check if enough approvals for multi-sig
(define-read-only (has-enough-approvals (tx-id uint))
  (match (map-get? pending-transactions { tx-id: tx-id })
    tx-data (let (
        (wallet-info (unwrap! (map-get? wallets { owner: (get from tx-data) })
          ERR-WALLET-NOT-FOUND
        ))
        (threshold (get multisig-threshold wallet-info))
        (current-approvals (get approval-count tx-data))
      )
      (ok (>= current-approvals threshold))
    )
    ERR-WALLET-NOT-FOUND
  )
)

;; Private functions

;; Verify passkey authorization (integrates with passkey-registry)
(define-private (verify-passkey-auth
    (owner principal)
    (passkey-id (buff 65))
  )
  (contract-call? .passkey-registry is-passkey-registered owner passkey-id)
)

;; Public functions

;; Initialize wallet for new user
(define-public (initialize-wallet (initial-threshold uint))
  (let ((owner tx-sender))
    ;; Ensure wallet doesn't already exist
    (asserts! (is-none (map-get? wallets { owner: owner })) ERR-WALLET-NOT-FOUND)

    ;; Validate threshold
    (asserts! (and (>= initial-threshold u1) (<= initial-threshold u10))
      ERR-INVALID-THRESHOLD
    )

    (map-set wallets { owner: owner } {
      balance: u0,
      nonce: u0,
      multisig-threshold: initial-threshold,
      total-passkeys: u0,
      created-at: stacks-block-height,
    })

    (ok true)
  )
)

;; Deposit STX to wallet
(define-public (deposit (amount uint))
  (let (
      (owner tx-sender)
      (wallet-data (unwrap! (map-get? wallets { owner: owner }) ERR-WALLET-NOT-FOUND))
      (current-balance (get balance wallet-data))
    )
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)

    ;; Transfer STX from user to contract
    (try! (stx-transfer? amount owner tx-sender))

    ;; Update wallet balance
    (map-set wallets { owner: owner }
      (merge wallet-data { balance: (+ current-balance amount) })
    )

    (ok true)
  )
)

;; Create a withdrawal transaction (requires multi-sig approval)
(define-public (create-withdrawal
    (to principal)
    (amount uint)
    (passkey-id (buff 65))
  )
  (let (
      (owner tx-sender)
      (wallet-data (unwrap! (map-get? wallets { owner: owner }) ERR-WALLET-NOT-FOUND))
      (current-balance (get balance wallet-data))
      (tx-id (var-get next-tx-id))
    )
    ;; Verify passkey is registered
    (asserts! (verify-passkey-auth owner passkey-id) ERR-PASSKEY-NOT-VERIFIED)

    ;; Check balance
    (asserts! (>= current-balance amount) ERR-INSUFFICIENT-BALANCE)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)

    ;; Create pending transaction
    (map-set pending-transactions { tx-id: tx-id } {
      from: owner,
      to: to,
      amount: amount,
      approvals: (list passkey-id),
      approval-count: u1,
      created-at: stacks-block-height,
      executed: false,
    })

    ;; Increment transaction ID
    (var-set next-tx-id (+ tx-id u1))

    ;; Update passkey usage
    (try! (contract-call? .passkey-registry update-passkey-usage passkey-id))

    (ok tx-id)
  )
)

;; Approve a pending transaction with another passkey (multi-sig)
;; Uses list-filter-map concept for managing approvals
(define-public (approve-transaction
    (tx-id uint)
    (passkey-id (buff 65))
  )
  (let (
      (owner tx-sender)
      (tx-data (unwrap! (map-get? pending-transactions { tx-id: tx-id })
        ERR-WALLET-NOT-FOUND
      ))
      (current-approvals (get approvals tx-data))
    )
    ;; Verify transaction belongs to sender
    (asserts! (is-eq owner (get from tx-data)) ERR-NOT-AUTHORIZED)

    ;; Verify passkey is registered
    (asserts! (verify-passkey-auth owner passkey-id) ERR-PASSKEY-NOT-VERIFIED)

    ;; Check transaction not already executed
    (asserts! (not (get executed tx-data)) ERR-NOT-AUTHORIZED)

    ;; Add approval (using concat - similar to list-concat)
    (map-set pending-transactions { tx-id: tx-id }
      (merge tx-data {
        approvals: (unwrap-panic (as-max-len? (concat current-approvals (list passkey-id)) u10)),
        approval-count: (+ (get approval-count tx-data) u1),
      })
    )

    ;; Update passkey usage
    (try! (contract-call? .passkey-registry update-passkey-usage passkey-id))

    (ok true)
  )
)

;; Execute a pending transaction once threshold is met
(define-public (execute-transaction (tx-id uint))
  (let (
      (owner tx-sender)
      (tx-data (unwrap! (map-get? pending-transactions { tx-id: tx-id })
        ERR-WALLET-NOT-FOUND
      ))
      (wallet-data (unwrap! (map-get? wallets { owner: owner }) ERR-WALLET-NOT-FOUND))
      (has-approvals (try! (has-enough-approvals tx-id)))
    )
    ;; Verify transaction belongs to sender
    (asserts! (is-eq owner (get from tx-data)) ERR-NOT-AUTHORIZED)

    ;; Check transaction not already executed
    (asserts! (not (get executed tx-data)) ERR-NOT-AUTHORIZED)

    ;; Check threshold met
    (asserts! has-approvals ERR-MULTISIG-THRESHOLD-NOT-MET)

    ;; Transfer STX from contract to recipient
    (try! (stx-transfer? (get amount tx-data) tx-sender (get to tx-data)))

    ;; Update wallet balance
    (map-set wallets { owner: owner }
      (merge wallet-data {
        balance: (- (get balance wallet-data) (get amount tx-data)),
        nonce: (+ (get nonce wallet-data) u1),
      })
    )

    ;; Mark transaction as executed
    (map-set pending-transactions { tx-id: tx-id }
      (merge tx-data { executed: true })
    )

    (ok true)
  )
)

;; Update multi-sig threshold
(define-public (set-multisig-threshold (new-threshold uint))
  (let (
      (owner tx-sender)
      (wallet-data (unwrap! (map-get? wallets { owner: owner }) ERR-WALLET-NOT-FOUND))
    )
    ;; Validate threshold
    (asserts!
      (and (>= new-threshold u1) (<= new-threshold (get total-passkeys wallet-data)))
      ERR-INVALID-THRESHOLD
    )

    (map-set wallets { owner: owner }
      (merge wallet-data { multisig-threshold: new-threshold })
    )

    (ok true)
  )
)

;; Direct transfer (for single-sig wallets with threshold = 1)
(define-public (transfer
    (amount uint)
    (to principal)
    (passkey-id (buff 65))
  )
  (let (
      (owner tx-sender)
      (wallet-data (unwrap! (map-get? wallets { owner: owner }) ERR-WALLET-NOT-FOUND))
    )
    ;; Only allow if threshold is 1
    (asserts! (is-eq (get multisig-threshold wallet-data) u1) ERR-NOT-AUTHORIZED)

    ;; Verify passkey
    (asserts! (verify-passkey-auth owner passkey-id) ERR-PASSKEY-NOT-VERIFIED)

    ;; Check balance
    (asserts! (>= (get balance wallet-data) amount) ERR-INSUFFICIENT-BALANCE)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)

    ;; Transfer STX
    (try! (stx-transfer? amount tx-sender to))

    ;; Update balance and nonce
    (map-set wallets { owner: owner }
      (merge wallet-data {
        balance: (- (get balance wallet-data) amount),
        nonce: (+ (get nonce wallet-data) u1),
      })
    )

    ;; Update passkey usage
    (try! (contract-call? .passkey-registry update-passkey-usage passkey-id))

    (ok true)
  )
)
;; Wallet Core with Protocol Fees and Chainhook Events
(define-constant TREASURY 'STNHKEPYEPJ8ET55ZZ0M5A34J0R3N5FM2CMMMAZ6)
(define-constant REGISTRATION-FEE u1000000) ;; 1 STX protocol fee
(define-constant TRANSACTION-FEE u50000)    ;; 0.05 STX service fee

(define-constant ERR-NOT-AUTHORIZED u200)
(define-constant ERR-INSUFFICIENT-BALANCE u201)
(define-constant ERR-WALLET-NOT-FOUND u203)
(define-constant ERR-MULTISIG-THRESHOLD-NOT-MET u205)

(define-map wallets
  { owner: principal }
  { balance: uint, nonce: uint, multisig-threshold: uint }
)

(define-map pending-transactions
  { tx-id: uint }
  { from: principal, to: principal, amount: uint, approvals: (list 10 (buff 65)), executed: bool }
)

(define-data-var next-tx-id uint u0)

;; Read-only: Get Revenue Status
(define-read-only (get-protocol-treasury)
  (ok TREASURY)
)

(define-public (initialize-wallet (initial-threshold uint))
  (let ((owner tx-sender))
    (asserts! (is-none (map-get? wallets { owner: owner })) (err ERR-NOT-AUTHORIZED))
    
    ;; COLLECT PROTOCOL REVENUE
    (try! (stx-transfer? REGISTRATION-FEE tx-sender TREASURY))

    (map-set wallets { owner: owner } {
      balance: u0,
      nonce: u0,
      multisig-threshold: initial-threshold
    })

    ;; CHAINHOOK EVENT
    (print { event: "wallet-created", owner: owner, fee-paid: REGISTRATION-FEE })
    (ok true)
  )
)

(define-public (deposit (amount uint))
  (let (
      (owner tx-sender)
      (wallet-data (unwrap! (map-get? wallets { owner: owner }) (err ERR-WALLET-NOT-FOUND)))
    )
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (map-set wallets { owner: owner }
      (merge wallet-data { balance: (+ (get balance wallet-data) amount) })
    )
    (print { event: "deposit", owner: owner, amount: amount })
    (ok true)
  )
)

(define-public (create-withdrawal (to principal) (amount uint) (passkey-id (buff 65)))
  (let (
      (owner tx-sender)
      (tx-id (var-get next-tx-id))
      (wallet-data (unwrap! (map-get? wallets { owner: owner }) (err ERR-WALLET-NOT-FOUND)))
    )
    (asserts! (>= (get balance wallet-data) (+ amount TRANSACTION-FEE)) (err ERR-INSUFFICIENT-BALANCE))
    
    (map-set pending-transactions { tx-id: tx-id } {
      from: owner,
      to: to,
      amount: amount,
      approvals: (list passkey-id),
      executed: false
    })

    (var-set next-tx-id (+ tx-id u1))
    (try! (contract-call? .passkey-registry update-passkey-usage passkey-id))
    
    ;; CHAINHOOK EVENT: Notifies user they created a pending tx
    (print { event: "tx-initiated", tx-id: tx-id, owner: owner, amount: amount })
    (ok tx-id)
  )
)

(define-public (execute-transaction (tx-id uint))
  (let (
      (owner tx-sender)
      (tx-data (unwrap! (map-get? pending-transactions { tx-id: tx-id }) (err ERR-WALLET-NOT-FOUND)))
      (wallet-data (unwrap! (map-get? wallets { owner: owner }) (err ERR-WALLET-NOT-FOUND)))
      (threshold (get multisig-threshold wallet-data))
    )
    (asserts! (>= (len (get approvals tx-data)) threshold) (err ERR-MULTISIG-THRESHOLD-NOT-MET))
    (asserts! (not (get executed tx-data)) (err ERR-NOT-AUTHORIZED))

    ;; PAY SERVICE FEE FROM WALLET BALANCE
    (try! (as-contract (stx-transfer? TRANSACTION-FEE (as-contract tx-sender) TREASURY)))
    
    ;; PAY WITHDRAWAL
    (try! (as-contract (stx-transfer? (get amount tx-data) (as-contract tx-sender) (get to tx-data))))

    (map-set wallets { owner: owner }
      (merge wallet-data { balance: (- (get balance wallet-data) (+ (get amount tx-data) TRANSACTION-FEE)) })
    )
    
    (map-set pending-transactions { tx-id: tx-id } (merge tx-data { executed: true }))

    ;; CHAINHOOK EVENT: Revenue generated
    (print { event: "tx-executed", tx-id: tx-id, fee-collected: TRANSACTION-FEE, amount: (get amount tx-data) })
    (ok true)
  )
)
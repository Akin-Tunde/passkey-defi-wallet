;; Recovery Guardian Contract - Final Improved Version
;; Features: Social Recovery, Timelocks, Unanimous Emergency Bypass

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-GUARDIAN-EXISTS (err u401))
(define-constant ERR-GUARDIAN-NOT-FOUND (err u402))
(define-constant ERR-MAX-GUARDIANS-REACHED (err u403))
(define-constant ERR-RECOVERY-NOT-ACTIVE (err u404))
(define-constant ERR-RECOVERY-ALREADY-ACTIVE (err u405))
(define-constant ERR-THRESHOLD-NOT-MET (err u406))
(define-constant ERR-TIMELOCK-NOT-EXPIRED (err u407))
(define-constant ERR-INVALID-THRESHOLD (err u408))
(define-constant ERR-CANNOT-BE-OWN-GUARDIAN (err u409))
(define-constant ERR-DUPLICATE-APPROVAL (err u410))

(define-constant MAX-GUARDIANS u10)
(define-constant RECOVERY-TIMELOCK u144) ;; ~24 hours (144 * 10 min blocks)

;; Data structures
(define-map guardians
  { owner: principal, guardian: principal }
  { added-at: uint, is-active: bool }
)

(define-map account-guardians
  { owner: principal }
  {
    guardian-list: (list 10 principal),
    guardian-threshold: uint,
    total-guardians: uint
  }
)

(define-map recovery-requests
  { owner: principal }
  {
    new-owner: principal,
    approvals: (list 10 principal),
    approval-count: uint,
    initiated-at: uint,
    is-active: bool,
    executed: bool
  }
)

;; --- Read-only functions ---

(define-read-only (get-account-guardians (owner principal))
  (default-to { guardian-list: (list), guardian-threshold: u0, total-guardians: u0 }
    (map-get? account-guardians { owner: owner }))
)

(define-read-only (is-guardian (owner principal) (guardian principal))
  (match (map-get? guardians { owner: owner, guardian: guardian })
    guardian-data (get is-active guardian-data)
    false
  )
)

(define-read-only (get-recovery-request (owner principal))
  (map-get? recovery-requests { owner: owner })
)

;; --- Private functions ---

(define-private (is-standard-principal (p principal))
  ;; Check-checker validation: Ensure principal is not a contract and is standard
  (is-standard p)
)

;; --- Public functions ---

;; Add a guardian to your account
(define-public (add-guardian (guardian principal))
  (let (
      (owner tx-sender)
      (current-config (get-account-guardians owner))
      (guardian-list (get guardian-list current-config))
    )
    ;; 1. Validation (Fixes Check-checker warnings)
    (asserts! (is-standard-principal guardian) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-eq guardian owner)) ERR-CANNOT-BE-OWN-GUARDIAN)
    (asserts! (is-none (map-get? guardians { owner: owner, guardian: guardian })) ERR-GUARDIAN-EXISTS)
    (asserts! (< (get total-guardians current-config) MAX-GUARDIANS) ERR-MAX-GUARDIANS-REACHED)

    ;; 2. Update state using Clarity 4 concat
    (map-set guardians { owner: owner, guardian: guardian } { added-at: stacks-block-height, is-active: true })
    (map-set account-guardians { owner: owner } {
      guardian-list: (unwrap-panic (as-max-len? (concat guardian-list (list guardian)) u10)),
      guardian-threshold: (get guardian-threshold current-config),
      total-guardians: (+ (get total-guardians current-config) u1)
    })
    (ok true)
  )
)

;; Set how many guardians are needed to approve recovery
(define-public (set-guardian-threshold (threshold uint))
  (let (
      (owner tx-sender)
      (current-config (get-account-guardians owner))
    )
    (asserts! (and (>= threshold u1) (<= threshold (get total-guardians current-config))) ERR-INVALID-THRESHOLD)
    (map-set account-guardians { owner: owner }
      (merge current-config { guardian-threshold: threshold })
    )
    (ok true)
  )
)

;; Step 1 of Recovery: A guardian starts the process
(define-public (initiate-recovery (account-owner principal) (new-owner principal))
  (let (
      (caller tx-sender)
      (is-auth (is-guardian account-owner caller))
    )
    (asserts! is-auth ERR-NOT-AUTHORIZED)
    (asserts! (is-standard-principal new-owner) ERR-NOT-AUTHORIZED)
    
    ;; Ensure no recovery is already running
    (match (map-get? recovery-requests { owner: account-owner })
      request (asserts! (not (get is-active request)) ERR-RECOVERY-ALREADY-ACTIVE)
      true
    )

    (map-set recovery-requests { owner: account-owner } {
      new-owner: new-owner,
      approvals: (list caller),
      approval-count: u1,
      initiated-at: stacks-block-height,
      is-active: true,
      executed: false
    })
    (print { event: "recovery-initiated", owner: account-owner, by: caller })
    (ok true)
  )
)

;; Step 2 of Recovery: Other guardians vote
(define-public (approve-recovery (account-owner principal))
  (let (
      (caller tx-sender)
      (request (unwrap! (map-get? recovery-requests { owner: account-owner }) ERR-RECOVERY-NOT-ACTIVE))
      (current-approvals (get approvals request))
    )
    ;; 1. Check if caller is an authorized guardian
    (asserts! (is-guardian account-owner caller) ERR-NOT-AUTHORIZED)
    ;; 2. Prevent duplicate voting
    (asserts! (is-none (index-of current-approvals caller)) ERR-DUPLICATE-APPROVAL)
    ;; 3. Ensure recovery is active
    (asserts! (get is-active request) ERR-RECOVERY-NOT-ACTIVE)

    (map-set recovery-requests { owner: account-owner }
      (merge request {
        approvals: (unwrap-panic (as-max-len? (concat current-approvals (list caller)) u10)),
        approval-count: (+ (get approval-count request) u1)
      })
    )
    (ok true)
  )
)

;; Step 3: Execution after timelock (Standard Path)
(define-public (execute-recovery (account-owner principal))
  (let (
      (request (unwrap! (map-get? recovery-requests { owner: account-owner }) ERR-RECOVERY-NOT-ACTIVE))
      (config (get-account-guardians account-owner))
      (blocks-passed (- stacks-block-height (get initiated-at request)))
    )
    (asserts! (get is-active request) ERR-RECOVERY-NOT-ACTIVE)
    (asserts! (>= (get approval-count request) (get guardian-threshold config)) ERR-THRESHOLD-NOT-MET)
    (asserts! (>= blocks-passed RECOVERY-TIMELOCK) ERR-TIMELOCK-NOT-EXPIRED)

    ;; Finalize
    (map-set recovery-requests { owner: account-owner } (merge request { is-active: false, executed: true }))
    
    ;; In a real integration, here you would call wallet-core to update the owner
    (print { event: "recovery-executed", owner: account-owner, new-owner: (get new-owner request) })
    (ok (get new-owner request))
  )
)

;; Emergency Path: If ALL guardians agree, bypass the 24h timelock
(define-public (emergency-recovery (account-owner principal))
  (let (
      (request (unwrap! (map-get? recovery-requests { owner: account-owner }) ERR-RECOVERY-NOT-ACTIVE))
      (config (get-account-guardians account-owner))
    )
    ;; Requires UNANIMOUS consent (all guardians)
    (asserts! (is-eq (get approval-count request) (get total-guardians config)) ERR-THRESHOLD-NOT-MET)
    
    (map-set recovery-requests { owner: account-owner } (merge request { is-active: false, executed: true }))
    (ok (get new-owner request))
  )
)

;; Cancellation: The original owner can cancel if they still have access
(define-public (cancel-recovery)
  (let (
      (owner tx-sender)
      (request (unwrap! (map-get? recovery-requests { owner: owner }) ERR-RECOVERY-NOT-ACTIVE))
    )
    (asserts! (not (get executed request)) ERR-NOT-AUTHORIZED)
    (map-set recovery-requests { owner: owner } (merge request { is-active: false }))
    (print { event: "recovery-cancelled", owner: owner })
    (ok true)
  )
)

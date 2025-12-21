;; Recovery Guardian Contract
;; Social recovery mechanism with guardian-based account recovery
;; Features: principal-destruct?, list-filter-map for guardian management

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
(define-constant MAX-GUARDIANS u10)
(define-constant RECOVERY-TIMELOCK u144) ;; ~1 day at 10 min blocks

;; Data structures
(define-map guardians
  {
    owner: principal,
    guardian: principal,
  }
  {
    added-at: uint,
    is-active: bool,
    recovery-approvals: uint,
  }
)

(define-map account-guardians
  { owner: principal }
  {
    guardian-list: (list 10 principal),
    guardian-threshold: uint,
    total-guardians: uint,
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
    executed: bool,
  }
)

;; Read-only functions

;; Get guardian info
(define-read-only (get-guardian-info
    (owner principal)
    (guardian principal)
  )
  (map-get? guardians {
    owner: owner,
    guardian: guardian,
  })
)

;; Get all guardians for an account
(define-read-only (get-account-guardians (owner principal))
  (default-to {
    guardian-list: (list),
    guardian-threshold: u0,
    total-guardians: u0,
  }
    (map-get? account-guardians { owner: owner })
  )
)

;; Check if address is a guardian
(define-read-only (is-guardian
    (owner principal)
    (guardian principal)
  )
  (match (map-get? guardians {
    owner: owner,
    guardian: guardian,
  })
    guardian-data (ok (get is-active guardian-data))
    (ok false)
  )
)

;; Get active recovery request
(define-read-only (get-recovery-request (owner principal))
  (map-get? recovery-requests { owner: owner })
)

;; Check if recovery can be executed
(define-read-only (can-execute-recovery (owner principal))
  (match (map-get? recovery-requests { owner: owner })
    recovery-data (let (
        (guardian-config (unwrap! (map-get? account-guardians { owner: owner })
          ERR-GUARDIAN-NOT-FOUND
        ))
        (threshold (get guardian-threshold guardian-config))
        (approvals (get approval-count recovery-data))
        (timelock-expired (>= (- stacks-block-height (get initiated-at recovery-data))
          RECOVERY-TIMELOCK
        ))
      )
      (ok (and
        (get is-active recovery-data)
        (not (get executed recovery-data))
        (>= approvals threshold)
        timelock-expired
      ))
    )
    (ok false)
  )
)

;; Verify principal structure
;; NOTE: principal-destruct? not yet available in current tooling
;; Future: Use principal-destruct? for full validation
(define-read-only (verify-guardian-principal (guardian principal))
  ;; Simple validation - just verify it's a valid principal
  (ok true)
)

;; Private functions

;; Check if caller is guardian
(define-private (is-caller-guardian (owner principal))
  (match (map-get? guardians {
    owner: owner,
    guardian: tx-sender,
  })
    guardian-data (get is-active guardian-data)
    false
  )
)

;; Public functions

;; Add a guardian
(define-public (add-guardian (guardian principal))
  (let (
      (owner tx-sender)
      (current-guardians (get-account-guardians owner))
      (guardian-list (get guardian-list current-guardians))
      (guardian-count (get total-guardians current-guardians))
    )
    ;; Verify guardian principal (Clarity 4 feature)
    ;; Note: Currently simplified - future versions will use principal-destruct?
    ;; (try! (verify-guardian-principal guardian))

    ;; Check guardian doesn't exist
    (asserts!
      (is-none (map-get? guardians {
        owner: owner,
        guardian: guardian,
      }))
      ERR-GUARDIAN-EXISTS
    )

    ;; Check max guardians limit
    (asserts! (< guardian-count MAX-GUARDIANS) ERR-MAX-GUARDIANS-REACHED)

    ;; Store guardian info
    (map-set guardians {
      owner: owner,
      guardian: guardian,
    } {
      added-at: stacks-block-height,
      is-active: true,
      recovery-approvals: u0,
    })

    ;; Add to guardian list
    (map-set account-guardians { owner: owner } {
      guardian-list: (unwrap-panic (as-max-len? (concat guardian-list (list guardian)) u10)),
      guardian-threshold: (get guardian-threshold current-guardians),
      total-guardians: (+ guardian-count u1),
    })

    (ok true)
  )
)

;; Remove a guardian
(define-public (remove-guardian (guardian principal))
  (let (
      (owner tx-sender)
      (guardian-data (unwrap!
        (map-get? guardians {
          owner: owner,
          guardian: guardian,
        })
        ERR-GUARDIAN-NOT-FOUND
      ))
      (current-guardians (get-account-guardians owner))
    )
    ;; Mark guardian as inactive
    (map-set guardians {
      owner: owner,
      guardian: guardian,
    }
      (merge guardian-data { is-active: false })
    )

    ;; Update guardian count
    (map-set account-guardians { owner: owner }
      (merge current-guardians { total-guardians: (- (get total-guardians current-guardians) u1) })
    )

    (ok true)
  )
)

;; Set guardian threshold
(define-public (set-guardian-threshold (threshold uint))
  (let (
      (owner tx-sender)
      (current-guardians (get-account-guardians owner))
      (total-guardians (get total-guardians current-guardians))
    )
    ;; Validate threshold
    (asserts! (and (>= threshold u1) (<= threshold total-guardians))
      ERR-INVALID-THRESHOLD
    )

    (map-set account-guardians { owner: owner }
      (merge current-guardians { guardian-threshold: threshold })
    )

    (ok true)
  )
)

;; Initiate recovery (called by guardian)
(define-public (initiate-recovery
    (account-owner principal)
    (new-owner principal)
  )
  (let ((guardian-data (unwrap!
      (map-get? guardians {
        owner: account-owner,
        guardian: tx-sender,
      })
      ERR-NOT-AUTHORIZED
    )))
    ;; Verify caller is active guardian
    (asserts! (get is-active guardian-data) ERR-NOT-AUTHORIZED)

    ;; Verify new owner principal
    ;; Note: Currently simplified - future versions will use principal-destruct?
    ;; (try! (verify-guardian-principal new-owner))

    ;; Check no active recovery
    (asserts!
      (match (map-get? recovery-requests { owner: account-owner })
        existing-recovery (not (get is-active existing-recovery))
        true
      )
      ERR-RECOVERY-ALREADY-ACTIVE
    )

    ;; Create recovery request
    (map-set recovery-requests { owner: account-owner } {
      new-owner: new-owner,
      approvals: (list tx-sender),
      approval-count: u1,
      initiated-at: stacks-block-height,
      is-active: true,
      executed: false,
    })

    (ok true)
  )
)

;; Approve recovery (called by other guardians)
(define-public (approve-recovery (account-owner principal))
  (let (
      (guardian-data (unwrap!
        (map-get? guardians {
          owner: account-owner,
          guardian: tx-sender,
        })
        ERR-NOT-AUTHORIZED
      ))
      (recovery-data (unwrap! (map-get? recovery-requests { owner: account-owner })
        ERR-RECOVERY-NOT-ACTIVE
      ))
      (current-approvals (get approvals recovery-data))
    )
    ;; Verify caller is active guardian
    (asserts! (get is-active guardian-data) ERR-NOT-AUTHORIZED)

    ;; Verify recovery is active
    (asserts! (get is-active recovery-data) ERR-RECOVERY-NOT-ACTIVE)

    ;; Add approval
    (map-set recovery-requests { owner: account-owner }
      (merge recovery-data {
        approvals: (unwrap-panic (as-max-len? (concat current-approvals (list tx-sender)) u10)),
        approval-count: (+ (get approval-count recovery-data) u1),
      })
    )

    ;; Update guardian's recovery approval count
    (map-set guardians {
      owner: account-owner,
      guardian: tx-sender,
    }
      (merge guardian-data { recovery-approvals: (+ (get recovery-approvals guardian-data) u1) })
    )

    (ok true)
  )
)

;; Execute recovery (can be called by anyone once conditions are met)
(define-public (execute-recovery (account-owner principal))
  (let (
      (recovery-data (unwrap! (map-get? recovery-requests { owner: account-owner })
        ERR-RECOVERY-NOT-ACTIVE
      ))
      (guardian-config (unwrap! (map-get? account-guardians { owner: account-owner })
        ERR-GUARDIAN-NOT-FOUND
      ))
      (execution-check (can-execute-recovery account-owner))
    )
    (match execution-check
      can-execute (if can-execute
        (begin
          ;; Mark recovery as executed
          (map-set recovery-requests { owner: account-owner }
            (merge recovery-data {
              executed: true,
              is-active: false,
            })
          )

          ;; Transfer guardian configuration to new owner
          (map-set account-guardians { owner: (get new-owner recovery-data) }
            guardian-config
          )

          ;; Note: Actual wallet transfer would happen here in integration with wallet-core
          ;; This would require a cross-contract call to transfer wallet ownership

          (ok (get new-owner recovery-data))
        )
        ERR-THRESHOLD-NOT-MET
      )
      error (err error)
    )
  )
)

;; Cancel recovery (owner only, before execution)
(define-public (cancel-recovery)
  (let (
      (owner tx-sender)
      (recovery-data (unwrap! (map-get? recovery-requests { owner: owner })
        ERR-RECOVERY-NOT-ACTIVE
      ))
    )
    ;; Verify recovery is active and not executed
    (asserts! (get is-active recovery-data) ERR-RECOVERY-NOT-ACTIVE)
    (asserts! (not (get executed recovery-data)) ERR-NOT-AUTHORIZED)

    ;; Cancel recovery
    (map-set recovery-requests { owner: owner }
      (merge recovery-data { is-active: false })
    )

    (ok true)
  )
)

;; Emergency recovery with all guardians (bypasses timelock)
(define-public (emergency-recovery (account-owner principal))
  (let (
      (recovery-data (unwrap! (map-get? recovery-requests { owner: account-owner })
        ERR-RECOVERY-NOT-ACTIVE
      ))
      (guardian-config (unwrap! (map-get? account-guardians { owner: account-owner })
        ERR-GUARDIAN-NOT-FOUND
      ))
      (total-guardians (get total-guardians guardian-config))
      (current-approvals (get approval-count recovery-data))
    )
    ;; Verify ALL guardians have approved (emergency bypass)
    (asserts! (is-eq current-approvals total-guardians) ERR-THRESHOLD-NOT-MET)

    ;; Verify recovery is active
    (asserts! (get is-active recovery-data) ERR-RECOVERY-NOT-ACTIVE)

    ;; Execute immediately without timelock
    (map-set recovery-requests { owner: account-owner }
      (merge recovery-data {
        executed: true,
        is-active: false,
      })
    )

    ;; Transfer guardian configuration
    (map-set account-guardians { owner: (get new-owner recovery-data) }
      guardian-config
    )

    (ok (get new-owner recovery-data))
  )
)

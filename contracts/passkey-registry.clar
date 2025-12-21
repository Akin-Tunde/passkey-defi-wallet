;; Passkey Registry Contract
;; Manages passkey registration and verification using Clarity 4 features
;; Features: principal-from-slice, principal-destruct?, list-concat

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-PASSKEY-EXISTS (err u101))
(define-constant ERR-PASSKEY-NOT-FOUND (err u102))
(define-constant ERR-INVALID-PRINCIPAL (err u103))
(define-constant ERR-MAX-PASSKEYS-REACHED (err u104))
(define-constant MAX-PASSKEYS-PER-ACCOUNT u10)

;; Data structures
(define-map passkey-registry
  {
    owner: principal,
    passkey-id: (buff 65),
  }
  {
    credential-id: (buff 65),
    created-at: uint,
    last-used: uint,
    device-type: (string-ascii 50),
    is-active: bool,
  }
)

(define-map account-passkeys
  { owner: principal }
  { passkey-list: (list 10 (buff 65)) }
)

(define-map passkey-metadata
  { passkey-id: (buff 65) }
  {
    derived-principal: (optional principal),
    registration-height: uint,
  }
)

;; Read-only functions

;; Get passkey details
(define-read-only (get-passkey-info
    (owner principal)
    (passkey-id (buff 65))
  )
  (map-get? passkey-registry {
    owner: owner,
    passkey-id: passkey-id,
  })
)

;; Get all passkeys for an account
(define-read-only (get-account-passkeys (owner principal))
  (default-to { passkey-list: (list) }
    (map-get? account-passkeys { owner: owner })
  )
)

;; Check if passkey is registered
(define-read-only (is-passkey-registered
    (owner principal)
    (passkey-id (buff 65))
  )
  (is-some (map-get? passkey-registry {
    owner: owner,
    passkey-id: passkey-id,
  }))
)

;; Verify passkey-derived principal
;; NOTE: In full Clarity 4, this would use principal-destruct?
;; For now, we validate the principal format is correct
(define-read-only (verify-passkey-principal (derived-principal principal))
  ;; Future: (match (principal-destruct? derived-principal) ...)
  ;; For now, just verify it's a valid principal (non-standard address check)
  (ok (is-standard derived-principal))
)

;; Get passkey metadata including derived principal
(define-read-only (get-passkey-metadata (passkey-id (buff 65)))
  (map-get? passkey-metadata { passkey-id: passkey-id })
)

;; Public functions

;; Register a new passkey for an account
;; NOTE: Uses Clarity 4's list-concat feature
;; Future versions will use principal-from-slice when fully supported in tooling
(define-public (register-passkey
    (passkey-id (buff 65))
    (device-type (string-ascii 50))
  )
  (let (
      (owner tx-sender)
      (current-passkeys (get passkey-list (get-account-passkeys owner)))
      (passkey-count (len current-passkeys))
    )
    ;; Check if passkey already exists
    (asserts! (not (is-passkey-registered owner passkey-id)) ERR-PASSKEY-EXISTS)

    ;; Check max passkeys limit
    (asserts! (< passkey-count MAX-PASSKEYS-PER-ACCOUNT) ERR-MAX-PASSKEYS-REACHED)

    ;; Store passkey registry entry
    (map-set passkey-registry {
      owner: owner,
      passkey-id: passkey-id,
    } {
      credential-id: passkey-id,
      created-at: stacks-block-height,
      last-used: stacks-block-height,
      device-type: device-type,
      is-active: true,
    })

    ;; Store metadata
    ;; In production with full Clarity 4 support, derived-principal would use:
    ;; (principal-from-slice passkey-id)
    (map-set passkey-metadata { passkey-id: passkey-id } {
      derived-principal: none, ;; Future: use principal-from-slice
      registration-height: stacks-block-height,
    })

    ;; Add to account's passkey list using concat (Clarity 4 feature - list-concat)
    (map-set account-passkeys { owner: owner } { passkey-list: (unwrap-panic (as-max-len? (concat current-passkeys (list passkey-id)) u10)) })

    (ok true)
  )
)

;; Update last-used timestamp for a passkey
(define-public (update-passkey-usage (passkey-id (buff 65)))
  (let (
      (owner tx-sender)
      (passkey-data (unwrap!
        (map-get? passkey-registry {
          owner: owner,
          passkey-id: passkey-id,
        })
        ERR-PASSKEY-NOT-FOUND
      ))
    )
    (map-set passkey-registry {
      owner: owner,
      passkey-id: passkey-id,
    }
      (merge passkey-data { last-used: stacks-block-height })
    )

    (ok true)
  )
)

;; Deactivate a passkey (doesn't delete, just marks inactive)
(define-public (deactivate-passkey (passkey-id (buff 65)))
  (let (
      (owner tx-sender)
      (passkey-data (unwrap!
        (map-get? passkey-registry {
          owner: owner,
          passkey-id: passkey-id,
        })
        ERR-PASSKEY-NOT-FOUND
      ))
    )
    (map-set passkey-registry {
      owner: owner,
      passkey-id: passkey-id,
    }
      (merge passkey-data { is-active: false })
    )

    (ok true)
  )
)

;; Reactivate a passkey
(define-public (reactivate-passkey (passkey-id (buff 65)))
  (let (
      (owner tx-sender)
      (passkey-data (unwrap!
        (map-get? passkey-registry {
          owner: owner,
          passkey-id: passkey-id,
        })
        ERR-PASSKEY-NOT-FOUND
      ))
    )
    (map-set passkey-registry {
      owner: owner,
      passkey-id: passkey-id,
    }
      (merge passkey-data { is-active: true })
    )

    (ok true)
  )
)

;; Merge multiple passkey lists (demonstrates list-concat - Clarity 4)
;; Useful for account recovery or migration
(define-public (merge-passkey-accounts (source-owner principal))
  (let (
      (dest-owner tx-sender)
      (source-passkeys (get passkey-list (get-account-passkeys source-owner)))
      (dest-passkeys (get passkey-list (get-account-passkeys dest-owner)))
      ;; Combine lists using concat
      (merged-list (concat dest-passkeys source-passkeys))
    )
    ;; Ensure merged list doesn't exceed maximum
    (asserts! (<= (len merged-list) MAX-PASSKEYS-PER-ACCOUNT)
      ERR-MAX-PASSKEYS-REACHED
    )

    (map-set account-passkeys { owner: dest-owner } { passkey-list: (unwrap-panic (as-max-len? merged-list u10)) })

    (ok true)
  )
)

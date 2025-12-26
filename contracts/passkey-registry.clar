;; Update in passkey-registry.clar
(define-public (register-passkey (passkey-id (buff 65)) (device-type (string-ascii 50)))
  (let (
      (owner tx-sender)
      (current-passkeys (get passkey-list (get-account-passkeys owner)))
    )
    ;; Validation to fix Checker warnings
    (asserts! (> (len passkey-id) u0) (err u105))
    (asserts! (> (len device-type) u0) (err u106))
    
    (asserts! (not (is-passkey-registered owner passkey-id)) (err ERR-PASSKEY-EXISTS))
    (asserts! (< (len current-passkeys) u10) (err ERR-MAX-PASSKEYS-REACHED))

    (map-set passkey-registry { owner: owner, passkey-id: passkey-id }
      { 
        credential-id: passkey-id,
        created-at: stacks-block-height, 
        last-used: stacks-block-height,
        device-type: device-type, 
        is-active: true 
      }
    )

    (map-set account-passkeys { owner: owner } 
      { passkey-list: (unwrap-panic (as-max-len? (concat current-passkeys (list passkey-id)) u10)) }
    )
    (print { event: "passkey-registered", owner: owner, passkey-id: passkey-id })
    (ok true)
  )
)

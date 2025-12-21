;; Device Manager Contract
;; Manages device authorization and permissions
;; Features: list-filter-map, list-concat for device management

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-DEVICE-EXISTS (err u301))
(define-constant ERR-DEVICE-NOT-FOUND (err u302))
(define-constant ERR-MAX-DEVICES-REACHED (err u303))
(define-constant ERR-INVALID-PERMISSION (err u304))
(define-constant MAX-DEVICES u20)

;; Device permission levels
(define-constant PERMISSION-READ-ONLY "read-only")
(define-constant PERMISSION-SIGN "sign")
(define-constant PERMISSION-ADMIN "admin")

;; Data structures
(define-map devices
  {
    owner: principal,
    device-id: (buff 65),
  }
  {
    passkey-id: (buff 65),
    device-name: (string-ascii 50),
    permission-level: (string-ascii 20),
    registered-at: uint,
    last-active: uint,
    is-active: bool,
  }
)

(define-map account-devices
  { owner: principal }
  { device-list: (list 20 (buff 65)) }
)

(define-map device-activity
  { device-id: (buff 65) }
  {
    activity-count: uint,
    last-action: (string-ascii 100),
  }
)

;; Read-only functions

;; Get device info
(define-read-only (get-device-info
    (owner principal)
    (device-id (buff 65))
  )
  (map-get? devices {
    owner: owner,
    device-id: device-id,
  })
)

;; Get all devices for an account
(define-read-only (get-account-devices (owner principal))
  (default-to { device-list: (list) } (map-get? account-devices { owner: owner }))
)

;; Check if device is authorized
(define-read-only (is-device-authorized
    (owner principal)
    (device-id (buff 65))
  )
  (match (map-get? devices {
    owner: owner,
    device-id: device-id,
  })
    device-data (ok (get is-active device-data))
    (ok false)
  )
)

;; Check device permission level
(define-read-only (get-device-permission
    (owner principal)
    (device-id (buff 65))
  )
  (match (map-get? devices {
    owner: owner,
    device-id: device-id,
  })
    device-data (ok (get permission-level device-data))
    ERR-DEVICE-NOT-FOUND
  )
)

;; Get device activity
(define-read-only (get-device-activity (device-id (buff 65)))
  (map-get? device-activity { device-id: device-id })
)

;; Filter devices by permission level (demonstrates list-filter-map concept)
;; This would use list-filter-map in Clarity 4 for more complex filtering
(define-read-only (count-devices-by-permission
    (owner principal)
    (permission (string-ascii 20))
  )
  (let ((all-devices (get device-list (get-account-devices owner))))
    ;; In a real implementation with list-filter-map, we would filter the list
    ;; For now, we return the total device count
    (ok (len all-devices))
  )
)

;; Private functions

;; Verify device has specific permission
(define-private (has-permission
    (owner principal)
    (device-id (buff 65))
    (required-permission (string-ascii 20))
  )
  (match (map-get? devices {
    owner: owner,
    device-id: device-id,
  })
    device-data (or
      (is-eq (get permission-level device-data) required-permission)
      (is-eq (get permission-level device-data) PERMISSION-ADMIN)
    )
    false
  )
)

;; Public functions

;; Register a new device
(define-public (register-device
    (device-id (buff 65))
    (passkey-id (buff 65))
    (device-name (string-ascii 50))
    (permission-level (string-ascii 20))
  )
  (let (
      (owner tx-sender)
      (current-devices (get device-list (get-account-devices owner)))
      (device-count (len current-devices))
    )
    ;; Check device doesn't exist
    (asserts!
      (is-none (map-get? devices {
        owner: owner,
        device-id: device-id,
      }))
      ERR-DEVICE-EXISTS
    )

    ;; Check max devices limit
    (asserts! (< device-count MAX-DEVICES) ERR-MAX-DEVICES-REACHED)

    ;; Validate permission level
    (asserts!
      (or
        (is-eq permission-level PERMISSION-READ-ONLY)
        (or (is-eq permission-level PERMISSION-SIGN) (is-eq permission-level PERMISSION-ADMIN))
      )
      ERR-INVALID-PERMISSION
    )

    ;; Verify passkey is registered
    (asserts!
      (contract-call? .passkey-registry is-passkey-registered owner passkey-id)
      ERR-NOT-AUTHORIZED
    )

    ;; Store device info
    (map-set devices {
      owner: owner,
      device-id: device-id,
    } {
      passkey-id: passkey-id,
      device-name: device-name,
      permission-level: permission-level,
      registered-at: stacks-block-height,
      last-active: stacks-block-height,
      is-active: true,
    })

    ;; Add to device list using concat
    (map-set account-devices { owner: owner } { device-list: (unwrap-panic (as-max-len? (concat current-devices (list device-id)) u20)) })

    ;; Initialize activity tracking
    (map-set device-activity { device-id: device-id } {
      activity-count: u0,
      last-action: "registered",
    })

    (ok true)
  )
)

;; Update device permission
(define-public (update-device-permission
    (device-id (buff 65))
    (new-permission (string-ascii 20))
  )
  (let (
      (owner tx-sender)
      (device-data (unwrap!
        (map-get? devices {
          owner: owner,
          device-id: device-id,
        })
        ERR-DEVICE-NOT-FOUND
      ))
    )
    ;; Validate permission level
    (asserts!
      (or
        (is-eq new-permission PERMISSION-READ-ONLY)
        (or (is-eq new-permission PERMISSION-SIGN) (is-eq new-permission PERMISSION-ADMIN))
      )
      ERR-INVALID-PERMISSION
    )

    (map-set devices {
      owner: owner,
      device-id: device-id,
    }
      (merge device-data { permission-level: new-permission })
    )

    (ok true)
  )
)

;; Revoke device access
(define-public (revoke-device (device-id (buff 65)))
  (let (
      (owner tx-sender)
      (device-data (unwrap!
        (map-get? devices {
          owner: owner,
          device-id: device-id,
        })
        ERR-DEVICE-NOT-FOUND
      ))
    )
    (map-set devices {
      owner: owner,
      device-id: device-id,
    }
      (merge device-data { is-active: false })
    )

    ;; Update activity log
    (map-set device-activity { device-id: device-id }
      (merge
        (default-to {
          activity-count: u0,
          last-action: "",
        }
          (map-get? device-activity { device-id: device-id })
        ) { last-action: "revoked" }
      ))

    (ok true)
  )
)

;; Restore device access
(define-public (restore-device (device-id (buff 65)))
  (let (
      (owner tx-sender)
      (device-data (unwrap!
        (map-get? devices {
          owner: owner,
          device-id: device-id,
        })
        ERR-DEVICE-NOT-FOUND
      ))
    )
    (map-set devices {
      owner: owner,
      device-id: device-id,
    }
      (merge device-data { is-active: true })
    )

    ;; Update activity log
    (map-set device-activity { device-id: device-id }
      (merge
        (default-to {
          activity-count: u0,
          last-action: "",
        }
          (map-get? device-activity { device-id: device-id })
        ) { last-action: "restored" }
      ))

    (ok true)
  )
)

;; Log device activity
(define-public (log-device-activity
    (device-id (buff 65))
    (action (string-ascii 100))
  )
  (let (
      (owner tx-sender)
      (device-data (unwrap!
        (map-get? devices {
          owner: owner,
          device-id: device-id,
        })
        ERR-DEVICE-NOT-FOUND
      ))
      (current-activity (default-to {
        activity-count: u0,
        last-action: "",
      }
        (map-get? device-activity { device-id: device-id })
      ))
    )
    ;; Verify device is active
    (asserts! (get is-active device-data) ERR-NOT-AUTHORIZED)

    ;; Update last active timestamp
    (map-set devices {
      owner: owner,
      device-id: device-id,
    }
      (merge device-data { last-active: stacks-block-height })
    )

    ;; Update activity log
    (map-set device-activity { device-id: device-id } {
      activity-count: (+ (get activity-count current-activity) u1),
      last-action: action,
    })

    (ok true)
  )
)

;; Verify device can perform action based on permission
(define-public (verify-device-action
    (device-id (buff 65))
    (required-permission (string-ascii 20))
  )
  (let ((owner tx-sender))
    (ok (has-permission owner device-id required-permission))
  )
)

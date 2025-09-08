;; ContentLicensing.clar
;; Media Licensing Marketplace Smart Contract (corrected)
;; - Creators register media (title, rights, price, royalty-bps)
;; - Buyers purchase licenses (minted on-chain)
;; - Owners can list licenses for resale
;; - Buyers can buy listed licenses; royalty auto-splits
;; - Supports transfer and revocation

(define-constant ERR-UNAUTHORIZED u100)
(define-constant ERR-NOT-FOUND u101)
(define-constant ERR-INVALID u102)
(define-constant ERR-ZERO-PRICE u103)
(define-constant ERR-ALREADY-LISTED u104)
(define-constant ERR-NOT-LISTED u105)
(define-constant ERR-NOT-OWNER u106)
(define-constant ERR-TRANSFER-FAILED u107)

;; royalty is stored in basis points (bps), where 10000 = 100%

;; -----------------------------
;; Data structures
;; -----------------------------
(define-data-var next-media-id uint u0)
(define-data-var next-license-id uint u0)

;; media registry
(define-map media
  { id: uint }
  {
    creator: principal,
    title: (string-ascii 64),
    rights: (string-ascii 128),
    price: uint,
    royalty-bps: uint
  }
)

;; license token
(define-map licenses
  { id: uint }
  {
    media-id: uint,
    owner: principal,
    issued-at: uint,
    price-paid: uint
  }
)

;; listings for resale
(define-map listings
  { license-id: uint }
  {
    seller: principal,
    price: uint
  }
)

;; -----------------------------
;; Helpers / validators
;; -----------------------------
(define-private (assert-owner (who principal) (lid uint))
  (match (map-get? licenses { id: lid })
    license
    (let ((current (get owner license)))
      (asserts! (is-eq current who) (err ERR-NOT-OWNER))
      (ok true)
    )
    (err ERR-NOT-FOUND)
  )
)

(define-private (validate-royalty (bps uint))
  (begin
    ;; cap royalty to a reasonable value (e.g., <= 1000 bps = 10%)
    (asserts! (<= bps u1000) (err ERR-INVALID))
    (ok true)
  )
)

(define-private (safe-stx-transfer (amount uint) (sender principal) (recipient principal))
  (match (stx-transfer? amount sender recipient)
    tx-ok (ok true)
    tx-err (err ERR-TRANSFER-FAILED)
  )
)

;; -----------------------------
;; Public: Creator registers media
;; -----------------------------
(define-public (register-media (title (string-ascii 64)) (rights (string-ascii 128)) (price uint) (royalty-bps uint))
  (begin
    (asserts! (> price u0) (err ERR-ZERO-PRICE))
    (try! (validate-royalty royalty-bps))
    (let ((mid (+ (var-get next-media-id) u1)))
      (begin
        (map-set media { id: mid }
          { creator: tx-sender, title: title, rights: rights, price: price, royalty-bps: royalty-bps })
        (var-set next-media-id mid)
        (ok mid)
      )
    )
  )
)

;; -----------------------------
;; Public: Buy a new license (mint)
;; -----------------------------
(define-public (buy-license (mid uint))
  (match (map-get? media { id: mid })
    m
    (let ((media-price (get price m))
          (media-creator (get creator m)))
      (begin
        (asserts! (> media-price u0) (err ERR-ZERO-PRICE))
        (try! (safe-stx-transfer media-price tx-sender media-creator))
        (let ((lid (+ (var-get next-license-id) u1)))
          (map-set licenses { id: lid }
            { media-id: mid, owner: tx-sender, issued-at: stacks-block-height, price-paid: media-price })
          (var-set next-license-id lid)
          (ok lid)
        )
      )
    )
    (err ERR-NOT-FOUND)
  )
)

;; -----------------------------
;; Public: List a license for resale
;; -----------------------------
(define-public (list-license (lid uint) (list-price uint))
  (begin
    (asserts! (> list-price u0) (err ERR-ZERO-PRICE))
    (try! (assert-owner tx-sender lid))
    (asserts! (is-none (map-get? listings { license-id: lid })) (err ERR-ALREADY-LISTED))
    (map-set listings { license-id: lid } { seller: tx-sender, price: list-price })
    (ok true)
  )
)

;; -----------------------------
;; Public: Cancel listing
;; -----------------------------
(define-public (cancel-listing (lid uint))
  (match (map-get? listings { license-id: lid })
    entry
    (let ((listing-seller (get seller entry)))
      (begin
        (asserts! (is-eq listing-seller tx-sender) (err ERR-UNAUTHORIZED))
        (map-delete listings { license-id: lid })
        (ok true)
      )
    )
    (err ERR-NOT-LISTED)
  )
)

;; -----------------------------
;; Public: Buy a listed license (resale with royalty)
;; -----------------------------
(define-public (buy-listed-license (lid uint))
  (match (map-get? listings { license-id: lid })
    listing
    (let ((listing-seller (get seller listing))
          (listing-price (get price listing)))
      (match (map-get? licenses { id: lid })
        lic
        (let ((license-media-id (get media-id lic))
              (license-issued-at (get issued-at lic)))
          (match (map-get? media { id: license-media-id })
            m
            (let ((media-creator (get creator m))
                  (media-royalty-bps (get royalty-bps m)))
              (let (
                    (royalty-amount (/ (* listing-price media-royalty-bps) u10000))
                    (seller-amount (- listing-price (/ (* listing-price media-royalty-bps) u10000)))
                   )
                (begin
                  (try! (safe-stx-transfer royalty-amount tx-sender media-creator))
                  (try! (safe-stx-transfer seller-amount tx-sender listing-seller))
                  (map-set licenses { id: lid }
                    { media-id: license-media-id, owner: tx-sender, issued-at: license-issued-at, price-paid: listing-price })
                  (map-delete listings { license-id: lid })
                  (ok true)
                )
              )
            )
            (err ERR-NOT-FOUND)
          )
        )
        (err ERR-NOT-FOUND)
      )
    )
    (err ERR-NOT-LISTED)
  )
)

;; -----------------------------
;; Public: Transfer license (gift/off-chain)
;; -----------------------------
(define-public (transfer-license (lid uint) (new-owner principal))
  (match (map-get? licenses { id: lid })
    license-data
    (let ((license-media-id (get media-id license-data))
          (license-issued-at (get issued-at license-data))
          (license-price-paid (get price-paid license-data)))
      (begin
        (try! (assert-owner tx-sender lid))
        (map-set licenses { id: lid }
          { media-id: license-media-id,
            owner: new-owner,
            issued-at: license-issued-at,
            price-paid: license-price-paid })
        (ok true)
      )
    )
    (err ERR-NOT-FOUND)
  )
)

;; -----------------------------
;; Public: Creator revokes license
;; -----------------------------
(define-public (revoke-license (lid uint))
  (match (map-get? licenses { id: lid })
    lic
    (let ((license-media-id (get media-id lic)))
      (match (map-get? media { id: license-media-id })
        m
        (let ((media-creator (get creator m)))
          (begin
            (asserts! (is-eq media-creator tx-sender) (err ERR-UNAUTHORIZED))
            (map-delete licenses { id: lid })
            (map-delete listings { license-id: lid })
            (ok true)
          )
        )
        (err ERR-NOT-FOUND)
      )
    )
    (err ERR-NOT-FOUND)
  )
)

;; -----------------------------
;; Read-only views
;; -----------------------------
(define-read-only (get-media (mid uint))
  (map-get? media { id: mid })
)

(define-read-only (get-license (lid uint))
  (map-get? licenses { id: lid })
)

(define-read-only (get-listing (lid uint))
  (map-get? listings { license-id: lid })
)

(define-read-only (get-next-media-id)
  (ok (var-get next-media-id))
)

(define-read-only (get-next-license-id)
  (ok (var-get next-license-id))
)
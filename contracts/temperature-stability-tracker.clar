;; Temperature Stability Tracker Contract
;; Monitors cryogenic system performance and temperature fluctuation detection

;; Error codes
(define-constant ERR-UNAUTHORIZED (err u200))
(define-constant ERR-INVALID-TEMPERATURE (err u201))
(define-constant ERR-INVALID-PRESSURE (err u202))
(define-constant ERR-SYSTEM-NOT-FOUND (err u203))
(define-constant ERR-READING-NOT-FOUND (err u204))
(define-constant ERR-INVALID-POWER (err u205))
(define-constant ERR-COOLING-SYSTEM-OFFLINE (err u206))

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MIN-TEMPERATURE u1) ;; 1 mK minimum
(define-constant MAX-TEMPERATURE u5000) ;; 5K maximum
(define-constant TEMPERATURE-THRESHOLD u50) ;; 50 mK fluctuation threshold
(define-constant MIN-PRESSURE u1) ;; 1 mTorr minimum
(define-constant MAX-PRESSURE u100000) ;; 100 Torr maximum
(define-constant MIN-POWER u1) ;; 1 W minimum
(define-constant MAX-POWER u10000) ;; 10 kW maximum
(define-constant STABILITY-WINDOW u144) ;; 24 hours at 10-min blocks

;; Data structures
(define-map cooling-systems
  { system-id: (string-ascii 64) }
  {
    owner: principal,
    system-type: (string-ascii 32),
    base-temperature: uint,
    current-temperature: uint,
    pressure: uint,
    power-consumption: uint,
    helium-level: uint,
    nitrogen-level: uint,
    compressor-status: bool,
    pump-status: bool,
    last-update: uint,
    reading-count: uint,
    status: (string-ascii 20)
  }
)

(define-map temperature-readings
  { reading-id: uint }
  {
    system-id: (string-ascii 64),
    timestamp: uint,
    mixing-chamber-temp: uint,
    still-temp: uint,
    heat-exchanger-temp: uint,
    mc-pressure: uint,
    still-pressure: uint,
    compressor-power: uint,
    pump-power: uint,
    helium-flow-rate: uint,
    vibration-level: uint,
    magnetic-field: uint,
    validator: principal
  }
)

(define-map system-alerts
  { system-id: (string-ascii 64) }
  {
    temperature-alert: bool,
    pressure-alert: bool,
    power-alert: bool,
    helium-alert: bool,
    compressor-alert: bool,
    alert-count: uint,
    last-alert: uint
  }
)

(define-map stability-thresholds
  { system-id: (string-ascii 64) }
  {
    max-temp-fluctuation: uint,
    min-base-temp: uint,
    max-pressure: uint,
    max-power: uint,
    min-helium-level: uint,
    alert-enabled: bool
  }
)

(define-map authorized-technicians
  { technician: principal }
  { authorized: bool }
)

;; Data variables
(define-data-var reading-counter uint u0)
(define-data-var total-cooling-systems uint u0)
(define-data-var contract-paused bool false)
(define-data-var emergency-shutdown bool false)

;; Authorization functions
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT-OWNER)
)

(define-private (is-system-owner (system-id (string-ascii 64)))
  (match (map-get? cooling-systems { system-id: system-id })
    system-data (is-eq tx-sender (get owner system-data))
    false
  )
)

(define-private (is-authorized-technician)
  (default-to false (get authorized (map-get? authorized-technicians { technician: tx-sender })))
)

;; System registration functions
(define-public (register-cooling-system 
  (system-id (string-ascii 64))
  (system-type (string-ascii 32))
)
  (begin
    (asserts! (not (var-get contract-paused)) ERR-UNAUTHORIZED)
    (asserts! (is-none (map-get? cooling-systems { system-id: system-id })) ERR-UNAUTHORIZED)
    (map-set cooling-systems
      { system-id: system-id }
      {
        owner: tx-sender,
        system-type: system-type,
        base-temperature: u0,
        current-temperature: u0,
        pressure: u0,
        power-consumption: u0,
        helium-level: u100,
        nitrogen-level: u100,
        compressor-status: true,
        pump-status: true,
        last-update: stacks-block-height,
        reading-count: u0,
        status: "operational"
      }
    )
    (map-set stability-thresholds
      { system-id: system-id }
      {
        max-temp-fluctuation: TEMPERATURE-THRESHOLD,
        min-base-temp: u10,
        max-pressure: u1000,
        max-power: u5000,
        min-helium-level: u20,
        alert-enabled: true
      }
    )
    (map-set system-alerts
      { system-id: system-id }
      {
        temperature-alert: false,
        pressure-alert: false,
        power-alert: false,
        helium-alert: false,
        compressor-alert: false,
        alert-count: u0,
        last-alert: u0
      }
    )
    (var-set total-cooling-systems (+ (var-get total-cooling-systems) u1))
    (ok true)
  )
)

(define-public (update-stability-thresholds
  (system-id (string-ascii 64))
  (max-temp-fluctuation uint)
  (min-base-temp uint)
  (max-pressure uint)
  (max-power uint)
  (min-helium-level uint)
)
  (begin
    (asserts! (is-system-owner system-id) ERR-UNAUTHORIZED)
    (asserts! (>= min-base-temp MIN-TEMPERATURE) ERR-INVALID-TEMPERATURE)
    (asserts! (<= max-pressure MAX-PRESSURE) ERR-INVALID-PRESSURE)
    (asserts! (<= max-power MAX-POWER) ERR-INVALID-POWER)
    (map-set stability-thresholds
      { system-id: system-id }
      {
        max-temp-fluctuation: max-temp-fluctuation,
        min-base-temp: min-base-temp,
        max-pressure: max-pressure,
        max-power: max-power,
        min-helium-level: min-helium-level,
        alert-enabled: true
      }
    )
    (ok true)
  )
)

;; Temperature reading submission
(define-public (submit-temperature-reading
  (system-id (string-ascii 64))
  (mixing-chamber-temp uint)
  (still-temp uint)
  (heat-exchanger-temp uint)
  (mc-pressure uint)
  (still-pressure uint)
  (compressor-power uint)
  (pump-power uint)
  (helium-flow-rate uint)
  (vibration-level uint)
  (magnetic-field uint)
)
  (let
    (
      (reading-id (var-get reading-counter))
      (current-system (unwrap! (map-get? cooling-systems { system-id: system-id }) ERR-SYSTEM-NOT-FOUND))
    )
    (begin
      (asserts! (not (var-get contract-paused)) ERR-UNAUTHORIZED)
      (asserts! (not (var-get emergency-shutdown)) ERR-COOLING-SYSTEM-OFFLINE)
      (asserts! (is-authorized-technician) ERR-UNAUTHORIZED)
      (asserts! (>= mixing-chamber-temp MIN-TEMPERATURE) ERR-INVALID-TEMPERATURE)
      (asserts! (<= mixing-chamber-temp MAX-TEMPERATURE) ERR-INVALID-TEMPERATURE)
      (asserts! (>= still-temp MIN-TEMPERATURE) ERR-INVALID-TEMPERATURE)
      (asserts! (<= still-temp MAX-TEMPERATURE) ERR-INVALID-TEMPERATURE)
      (asserts! (>= mc-pressure MIN-PRESSURE) ERR-INVALID-PRESSURE)
      (asserts! (<= mc-pressure MAX-PRESSURE) ERR-INVALID-PRESSURE)
      (asserts! (<= compressor-power MAX-POWER) ERR-INVALID-POWER)
      (asserts! (<= pump-power MAX-POWER) ERR-INVALID-POWER)
      
      ;; Store reading
      (map-set temperature-readings
        { reading-id: reading-id }
        {
          system-id: system-id,
          timestamp: stacks-block-height,
          mixing-chamber-temp: mixing-chamber-temp,
          still-temp: still-temp,
          heat-exchanger-temp: heat-exchanger-temp,
          mc-pressure: mc-pressure,
          still-pressure: still-pressure,
          compressor-power: compressor-power,
          pump-power: pump-power,
          helium-flow-rate: helium-flow-rate,
          vibration-level: vibration-level,
          magnetic-field: magnetic-field,
          validator: tx-sender
        }
      )
      
      ;; Update system data
      (map-set cooling-systems
        { system-id: system-id }
        (merge current-system
          {
            base-temperature: mixing-chamber-temp,
            current-temperature: mixing-chamber-temp,
            pressure: mc-pressure,
            power-consumption: (+ compressor-power pump-power),
            last-update: stacks-block-height,
            reading-count: (+ (get reading-count current-system) u1)
          }
        )
      )
      
      (var-set reading-counter (+ reading-id u1))
      (ok reading-id)
    )
  )
)

;; System monitoring and alerting
(define-public (check-system-stability (system-id (string-ascii 64)))
  (let
    (
      (system-data (unwrap! (map-get? cooling-systems { system-id: system-id }) ERR-SYSTEM-NOT-FOUND))
      (thresholds (unwrap! (map-get? stability-thresholds { system-id: system-id }) ERR-SYSTEM-NOT-FOUND))
      (current-alerts (unwrap! (map-get? system-alerts { system-id: system-id }) ERR-SYSTEM-NOT-FOUND))
    )
    (let
      (
        (temp-violation (< (get base-temperature system-data) (get min-base-temp thresholds)))
        (pressure-violation (> (get pressure system-data) (get max-pressure thresholds)))
        (power-violation (> (get power-consumption system-data) (get max-power thresholds)))
        (helium-violation (< (get helium-level system-data) (get min-helium-level thresholds)))
        (compressor-issue (not (get compressor-status system-data)))
      )
      (begin
        ;; Update alerts if any violations detected
        (if (or temp-violation pressure-violation power-violation helium-violation compressor-issue)
          (map-set system-alerts
            { system-id: system-id }
            (merge current-alerts
              {
                temperature-alert: temp-violation,
                pressure-alert: pressure-violation,
                power-alert: power-violation,
                helium-alert: helium-violation,
                compressor-alert: compressor-issue,
                alert-count: (+ (get alert-count current-alerts) u1),
                last-alert: stacks-block-height
              }
            )
          )
          true
        )
        
        (ok {
          temperature-stable: (not temp-violation),
          pressure-stable: (not pressure-violation),
          power-stable: (not power-violation),
          helium-sufficient: (not helium-violation),
          compressor-operational: (not compressor-issue),
          system-stable: (and
            (not temp-violation)
            (not pressure-violation)
            (not power-violation)
            (not helium-violation)
            (not compressor-issue)
          )
        })
      )
    )
  )
)

(define-public (trigger-emergency-shutdown)
  (begin
    (asserts! (or (is-contract-owner) (is-authorized-technician)) ERR-UNAUTHORIZED)
    (var-set emergency-shutdown true)
    (ok true)
  )
)

(define-public (clear-emergency-shutdown)
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED)
    (var-set emergency-shutdown false)
    (ok true)
  )
)

;; System maintenance functions
(define-public (update-system-status
  (system-id (string-ascii 64))
  (compressor-status bool)
  (pump-status bool)
  (helium-level uint)
  (nitrogen-level uint)
)
  (let
    (
      (current-system (unwrap! (map-get? cooling-systems { system-id: system-id }) ERR-SYSTEM-NOT-FOUND))
    )
    (begin
      (asserts! (or (is-system-owner system-id) (is-authorized-technician)) ERR-UNAUTHORIZED)
      (map-set cooling-systems
        { system-id: system-id }
        (merge current-system
          {
            compressor-status: compressor-status,
            pump-status: pump-status,
            helium-level: helium-level,
            nitrogen-level: nitrogen-level,
            last-update: stacks-block-height
          }
        )
      )
      (ok true)
    )
  )
)

;; Administrative functions
(define-public (authorize-technician (technician principal))
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED)
    (map-set authorized-technicians { technician: technician } { authorized: true })
    (ok true)
  )
)

(define-public (revoke-technician (technician principal))
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED)
    (map-set authorized-technicians { technician: technician } { authorized: false })
    (ok true)
  )
)

(define-public (pause-contract)
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED)
    (var-set contract-paused true)
    (ok true)
  )
)

(define-public (resume-contract)
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED)
    (var-set contract-paused false)
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-cooling-system-info (system-id (string-ascii 64)))
  (map-get? cooling-systems { system-id: system-id })
)

(define-read-only (get-temperature-reading (reading-id uint))
  (map-get? temperature-readings { reading-id: reading-id })
)

(define-read-only (get-system-alerts (system-id (string-ascii 64)))
  (map-get? system-alerts { system-id: system-id })
)

(define-read-only (get-stability-thresholds (system-id (string-ascii 64)))
  (map-get? stability-thresholds { system-id: system-id })
)

(define-read-only (get-total-systems)
  (var-get total-cooling-systems)
)

(define-read-only (get-reading-count)
  (var-get reading-counter)
)

(define-read-only (is-technician-authorized (technician principal))
  (default-to false (get authorized (map-get? authorized-technicians { technician: technician })))
)

(define-read-only (get-contract-status)
  {
    paused: (var-get contract-paused),
    emergency-shutdown: (var-get emergency-shutdown),
    total-systems: (var-get total-cooling-systems),
    total-readings: (var-get reading-counter),
    owner: CONTRACT-OWNER
  }
)

;; title: temperature-stability-tracker
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;


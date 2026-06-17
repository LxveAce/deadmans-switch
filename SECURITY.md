# Security Policy

Dead Man's Switch is an anti-forensic dead-man gate for ESP32 security firmware. It is designed to
**permanently and irrecoverably destroy data** on the device it runs on — by design. It is built for
authorized, owner-only defensive use (see [`docs/SAFETY.md`](docs/SAFETY.md) and
[`docs/THREAT-MODEL.md`](docs/THREAT-MODEL.md)).

## Reporting a vulnerability

Email **lxveace@proton.me** with details and reproduction steps. Please do **not** open public
issues for security-sensitive reports. You will receive an acknowledgement within 72 hours;
coordinated disclosure is appreciated.

## Scope

Security reports are welcome for:

- **Bypass of the gate** — any path that allows firmware to boot without correct authentication when
  the device is provisioned and armed.
- **Password extraction** — any method to recover the plaintext password or reduce the PBKDF2 hash
  to a feasible brute-force target.
- **Wipe failure** — any condition where a triggered wipe leaves recoverable data on flash or SD.
- **Remote triggering** — any path that allows an unauthenticated remote actor to trigger a wipe
  (the dashboard commands are intentionally limited).
- **Host provisioning tool** — vulnerabilities in `host/provision.py` or the build scripts.

## Out of scope

- **Intended behavior** — the device is designed to wipe itself. Reports that the device wipes data
  when triggered are not vulnerabilities.
- **Physical attacks** — decapping the chip, JTAG/SWD debug access, or fault injection are within
  the documented threat model (see [`docs/THREAT-MODEL.md`](docs/THREAT-MODEL.md)).
- **T2 eFuse burns** — T2 tier deliberately burns eFuses. This is permanent and documented.

## Supported versions

The latest `master` is the supported version. Security fixes are applied to `master`.

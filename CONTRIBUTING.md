# Contributing to Dead Man's Switch

Thanks for your interest in contributing. This project deals with anti-forensic firmware that can
permanently destroy data, so contributions are held to a high bar for safety and correctness.

## Before you start

1. **Read the safety docs** — [`docs/SAFETY.md`](docs/SAFETY.md) and
   [`docs/THREAT-MODEL.md`](docs/THREAT-MODEL.md) are required reading.
2. **Read the spec** — [`docs/SPEC.md`](docs/SPEC.md) is the single source of truth for names, NVS
   keys, offsets, build flags, and the state machine. All contributions must be consistent with the
   spec.
3. **Build and test in SAFE MODE** — never test on hardware without `SUICIDE_SAFE_MODE=1`. See the
   build scripts in `scripts/`.

## How to contribute

1. Fork the repository and create a feature branch from `master`.
2. Make your changes. Keep commits focused and descriptive.
3. Ensure your code builds cleanly with the CI workflow (`.github/workflows/build.yml`).
4. Open a pull request against `master` with a clear description of what and why.

## What we look for

- **Safety first** — any change that touches the wipe path, gate logic, or provisioning must not
  weaken the safety invariants documented in `docs/SAFETY.md`.
- **Spec compliance** — changes to the interface contract must update `docs/SPEC.md` first.
- **Board support** — new board/chip support is welcome. Include the ROM SPI entry points, partition
  layout, and a hardware test log.
- **Documentation** — if your change affects user-facing behavior, update the relevant docs.

## Security issues

Do **not** open public issues for security vulnerabilities. See [`SECURITY.md`](SECURITY.md) for
the responsible disclosure process.

## License

By contributing, you agree that your contributions will be licensed under the
[MIT License](LICENSE).

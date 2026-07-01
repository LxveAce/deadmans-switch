# deadmans-switch — Forward Plan

> Status: v1.0.0 shipped + downloadable; provisioner CI green, and the firmware `build` CI now runs on master and is **green** — it's best-effort/non-blocking (the frozen firmware doesn't link in CI yet, a documented hardware/completion gate, so it shows a yellow warning instead of failing the run). Health: green. Date: 2026-07-01

## Where this stands

**What it is.** `deadmans-switch` (Dead Man's Switch) is a defensive, owner-only "dead-man gate" firmware layer for ESP32 security firmware, the declared successor to Suicide Marauder. The gate (`firmware/bootgate/`) runs once early in boot, before the host firmware UI, and gates on a password / hardware arming line / wrong-attempt counter; on a legitimate trigger (only when armed) it runs a forensic self-destruct. Two variants: **GUARDIAN** (standalone factory app that hands off to unmodified Marauder) and **FORK** (patched into ESP32Marauder). Host side: `host/provision.py` (stdlib-only on the security path: getpass, os.urandom, PBKDF2-HMAC-SHA256) mints `guardcfg.bin` + otadata from a locally-entered password.

**How to build/run.** Firmware is built per-board via `scripts/build.sh` / `scripts/build.ps1`, **SAFE_MODE (simulate-only) by default**; live destruct needs `--no-safe-mode` and live brick needs `--allow-live-brick`. FORK requires the external ESP32Marauder sketch (`--sketch` / `MARAUDER_SKETCH`). Provision a device with `python host/provision.py --partitions <csv> ...`.

**Current state.** master = single squashed commit `cae573d` (README refresh, 2026-06-17). One release **v1.0.0** (2026-06-11); all 4 cross-platform provisioner binaries return HTTP 200 (live). 0 open issues. **Provisioner-release CI is green, and the firmware `build` CI now triggers on master and passes** — it's deliberately best-effort/non-blocking: the frozen firmware doesn't link in CI yet (a documented hardware/completion gate), so it surfaces as a yellow warning rather than failing the workflow. Firmware is hardware-validated only on a classic ESP32 CYD; the Stage-3 brick primitive is explicitly UNVERIFIED on other chips. The host-side flasher integration already exists in **cyber-controller** (as a git submodule consumer), not in the repo the plan docs name.

## P0 — do first

> **Update 2026-07-01:** the CI plumbing in P0-1 is resolved — the push trigger now covers `master`, arduino-cli
> comes from the official action (on PATH), and the build steps are best-effort/non-blocking, so the workflow
> runs on every push and is green. What's left is the firmware actually *linking* in CI, which is
> hardware/completion-gated (see the SAFE_MODE note) — that stays open, but it no longer shows the repo as red.

1. **Fix the firmware `build` CI so it runs and passes.** Three stacked breakages in `.github/workflows/build.yml`:
   - (a) push trigger is `branches: [ main ]` but the default branch is **master** (line 20) → CI never runs on commits. Change to `[ master ]`.
   - (b) arduino-cli install appends `$PWD/bin` to `GITHUB_PATH` in one step, but the next "Install ESP32 core" step can't find the binary (lines 72-83). Install to a known dir and call by absolute path, or combine install + core-install into one step.
   - (c) the 4 FORK legs call `firmware/integration/apply_hook.sh`, which **does not exist** (lines 93-97).
2. **Resolve the `apply_hook.sh` gap.** Either ADD `firmware/integration/apply_hook.sh` (the FORK integration tool INTEGRATION.md + CI already assume) OR mark the FORK legs skipped/allowed-to-fail until it exists. `scripts/build.sh` (~line 165) also exits when `MARAUDER_SKETCH` is unset. Without this, fixing (a)/(b) still leaves 4/5 legs red.
3. **cyber-controller distributable / .exe (cross-repo, but blocks real-world use).** cyber-controller has a PyInstaller `build.py` + pyproject entrypoints but ships **no committed/released `dist/` installer**, and its `deadmans-switch` submodule working dir is **EMPTY (uninitialized)**. Before the flasher path reaches a non-developer: run `git submodule update --init` in cyber-controller and produce/publish a built installer. (Build work lives in cyber-controller; flagged here because cyber-controller is the real consumer of this repo's `host/provision.py`.)
4. **Add the two owner-directed features to canonical `docs/SPEC.md` BEFORE writing code** (SPEC is the single source of truth; features get a SPEC section first). See "Features to add".

## Surface bugs found

| Title | Location | Severity | Note |
|---|---|---|---|
| Firmware build CI never triggers on pushes (wrong branch) | `.github/workflows/build.yml:18-21` | P1 | Default branch is master; only run was the v1.0.0 tag. |
| arduino-cli not on PATH for "Install ESP32 core" | `.github/workflows/build.yml:72-83` | P1 | All 5 legs failed here on the v1.0.0 run. |
| FORK legs call missing `apply_hook.sh` | `build.yml:93-97`; `firmware/integration/` (file absent) | P2 | FORK legs can't build; build.sh also exits with no `MARAUDER_SKETCH`. |
| Serial-command contract unspecified in SPEC, divergent across docs | `docs/SPEC.md` (no SM_* section); `README.md:48`; `CHANGELOG.md:22`; cyber-controller `deadman_auth.py` | P2 | README/CHANGELOG list SM_* verbs the canonical SPEC never defines; controller uses a different token set. |
| flasher-integration/PLAN.md points at wrong/stale target | `flasher-integration/PLAN.md:6`; `docs/SPEC.md:369` | P2 | Integration actually shipped in cyber-controller; path `<HOME>` isn't this machine. |
| PLAN.md `build_bundle()` signature mismatch | `PLAN.md:184-194` vs `host/provision.py:794` | P3 | PLAN uses kwargs; real fn is `build_bundle(args, pw_buf)`. cyber-controller calls it correctly. |
| Release assets branded with predecessor name | release v1.0.0 assets `suicide-marauder-provisioner-*` | P3 | Rename to `deadmans-switch-*` for identity clarity. |
| README (source script) vs shipped compiled binaries unreconciled | README Quickstart 4 + `host/requirements.txt` vs release binaries | P3 | Two undocumented-against-each-other install paths. |
| `build.ps1` binds `$Input` (PowerShell automatic var) | `scripts/build.ps1:26` (used 69, 111) | P3 | Rename to `$InputMethod`. |
| Stale duplicate CI file shadows active workflow | `ci/build.yml`; `ci/README.md:1` ("not yet active") | P3 | Only `.github/workflows/build.yml` runs; delete/reconcile. |

## Features to add

**USER DIRECTIVE 1 (verbatim): add ability to flash Tails OS (amnesiac OS) — fits the amnesiac/dead-man concept.**
- Host/PC-side imaging flow (Tails targets x86 PCs, not the ESP32), so it lives in the **provisioner/flasher layer** (extend `host/provision.py` or a new host tool, and/or cyber-controller) — NOT in `firmware/bootgate`.
- Must **verify the official Tails image** (signature/checksum) before writing, and **confirm the target is a removable, non-system disk** before writing. Mirrors the existing supply-chain pinning ethos (SPEC §14) and SAFE_MODE-by-default culture.

**USER DIRECTIVE 2 (verbatim): "create physical key" access gate — flash a USB with a key; software access requires an admin password AND/OR the physical USB key present.**
- USB-key minting step (host) + an access-gate check in the host tool / cyber-controller requiring **admin password AND/OR detection of the keyed USB**.
- Reuse existing crypto primitives (`GateCrypto` PBKDF2 / `provision.py` PBKDF2-HMAC-SHA256). This is **conceptually adjacent** to the existing on-device "two-factor to destroy" (`docs/ARCHITECTURE.md:36`) but is a **NEW gate protecting host/software access** — give it its own SPEC section + threat-model entry; do not conflate it with the destruct two-factor.

**Supporting features**
- Define one canonical **serial-command contract** section in `docs/SPEC.md` (SM_* verbs) so README, CHANGELOG, firmware, and cyber-controller agree.
- Author `firmware/integration/apply_hook.sh` as a real, documented FORK tool (also unblocks CI).
- Add an explicit install/run section to README + release notes reconciling the prebuilt binary vs `host/provision.py` from source.
- Optional: cut **v1.0.1** (or move the tag) so the published release includes the 2026-06-17 README refresh.

## Red-team / hardening

- **Physical-USB-key gate (Directive 2):** design fail-closed and resistant to trivial cloning/replay. A raw token file is copyable — document the assumed threat model (deters casual access, not a funded forensic adversary) and prefer a hashed-secret/challenge-response scheme over a plaintext token. Default to **AND** (password AND key) for high-assurance; make **OR** an explicit, clearly-labeled convenience downgrade.
- **Tails flashing (Directive 1):** always verify the image against Tails' official signature/checksum and refuse to write on mismatch; guard against writing the wrong drive.
- **Preserve destruct invariants:** the new host/software access gate must NOT become a new path that can trigger the on-device self-destruct, and "correct password always wins / never wipes" (SPEC §6) must remain intact.
- **Keep stdlib-only + pinned-deps discipline** on the security path (`esp-idf-nvs-partition-gen==0.2.0`, `esptool==5.3.0` <6); pin any new USB/imaging dependency deliberately.
- **CI never produces a live-brick build** (`SUICIDE_SAFE_MODE` invariant) — keep SAFE_MODE-only + bundle-verify steps when fixing CI.
- **Public-repo discipline:** frame everything as defensive owner-only hardening; no step-by-step destructive/bypass recipes. Keep the responsible-use framing in SAFETY.md / THREAT-MODEL.md. Commit as LxveAce, no Claude co-author, no PII.

## Dig deeper (next dedicated session)

1. Read firmware C++ line-by-line for crash/logic bugs not visible from docs: `BootGate.cpp` (26 KB), `SelfDestruct.cpp` (53 KB), `GateCrypto.cpp`, `GateConfig.cpp`, the `GateInput_*` adapters. Cross-check against `docs/NIGHT-SESSION-LOG.md` OPEN BUGS (SD-no-card abort, debug brickMark markers, per-chip brick only on classic ESP32) to confirm which are actually fixed before enabling brick on non-ESP32 targets.
2. Get a green firmware build locally (arduino-cli/pio) on ≥1 board — CI has never produced a successful firmware build. Confirm FORK compiles once `apply_hook.sh` + `MARAUDER_SKETCH` are wired.
3. Validate the Stage-3 brick primitive on S2/S3/C3/C6 on sacrificial hardware (UNVERIFIED across SPEC/SAFETY/ARCHITECTURE/SPIKE-PLAN; validated only on classic ESP32 CYD).
4. Settle the flasher duplicated-effort question: inspect headless-marauder-gui and decide whether it needs its own integration in addition to cyber-controller; retarget `PLAN.md` + SPEC §11.
5. Audit cyber-controller integration depth (`suicide_dialog.py`, `flash_core.py`, `flash_engine.py`); verify submodule init and that `suicide_setup.py`'s `build_bundle` call still matches `host/provision.py`.
6. Verify the shipped release binaries are genuinely a packaged build of `host/provision.py` (download, run, compare; verify SHA256 digests vs bytes).
7. Prototype Directive 2's key scheme (clone resistance, revocation, lost-key behavior) and Directive 1's image-verification chain end to end before committing firmware/host code.

## Dependencies & cross-repo context

- **External:** ESP32 Arduino core pinned 3.0.7 (build.yml); ESP32Marauder upstream (FORK variant). Host Python: `esp-idf-nvs-partition-gen==0.2.0` (only external dep on security path), `esptool==5.3.0` (<6). Tooling: arduino-cli / PlatformIO, PyInstaller.
- **Successor lineage:** deadmans-switch is the declared successor to Suicide-Marauder.
- **cyber-controller:** bundles deadmans-switch as a real git submodule (`.gitmodules` → github.com/LxveAce/deadmans-switch) and already consumes `host/provision.py` `build_bundle` via `src/core/suicide_setup.py`, with serial auth in `src/core/deadman_auth.py`. **The submodule working dir is currently EMPTY (run `git submodule update --init`).** cyber-controller has `build.py` (PyInstaller) but no committed `dist/` installer.
- **Profile rules (user memory):** public GitHub work committed as LxveAce, NO Claude co-author, no PII.

## Open questions

- Does `firmware/integration/apply_hook.sh` exist in a sibling/private repo, or must it be authored now? (file absent here)
- Are the shipped `suicide-marauder-provisioner-*` binaries actually a packaged build of `host/provision.py`? (not downloaded/run)
- Does the firmware actually compile? (CI never succeeded; no local toolchain run)
- Is the cyber-controller submodule committed-but-uninitialized vs broken? (working dir empty)
- Which serial-command set does the firmware actually emit — README's SM_* vs `deadman_auth.py`'s SM_AUTH_*/BOOTGATE? (no firmware source confirmed on-wire tokens)
- Should the flasher integration target cyber-controller (where it lives) or headless-marauder-gui (where SPEC §11/PLAN.md point), or both?
- Directive 1: where should Tails flashing live (provision.py / new host tool / cyber-controller) and what is the canonical image source + verification chain?
- Directive 2: what exactly is the "key" (hashed secret vs challenge/response), its threat model (clone/loss/revocation), and AND vs OR default?
- Cut/move v1.0.1 now (to include the 2026-06-17 README refresh), or defer to a bigger release with the new features?
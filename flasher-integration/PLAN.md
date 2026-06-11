# Flasher integration plan — add the Suicide path (+ tooltips) to `headless-marauder-gui`

> **Scope:** additive only. Plain Marauder stays the core/default behavior. Every change here is
> behind a checkbox that is **off** by default. This implements SPEC §11 and §12.
> **Target repo:** `C:\Users\extra\projects\headless-marauder-gui` (`LxveAce/headless-marauder-gui`).
> **Owner-only DEFENSIVE tool.** Plaintext passwords are hashed host-side and the buffer is
> zeroized — never stored, never logged, never passed on a CLI argv.

This is a *plan*, not the implementation. It names real symbols and exact insertion points so the
integration task (workflow task #4) is mechanical. Line numbers are anchors at the time of writing;
re-confirm by symbol name, not by number.

---

## 0. Files touched

| File | Change |
|------|--------|
| `marauder_core/flasher.py` | add `suicide_bundle_files()` + `flash_suicide()` (reuse existing plumbing) |
| `gui_qt/app.py` | extend `FlasherDialog` (class at **:220**) with a Suicide sub-panel + a separate T2 checkbox; add a central `TIPS` dict and tooltip sweep extending `_cmd_tooltip()` (**:42**) |
| `gui/flasher_window.py` + `gui/app.py` | add a `Tooltip` helper (Tk has no native tooltip) + Suicide sub-panel mirror; tooltip sweep |
| `tui/app.py` | set `tooltip=` on widgets (Textual has native tooltips); Suicide sub-panel mirror |
| `marauder_core/__init__.py` | re-export `provision` so the GUI can hash host-side |
| `requirements.txt` | add `esp-idf-nvs-partition-gen` (confirmed NOT bundled with esptool) and pin; PBKDF2 uses stdlib `hashlib` (no new crypto dep) |
| `host/provision.py` *(in Suicide-Marauder repo)* | imported by the GUI process for host-side hashing + `guardcfg.bin` generation |

---

## 1. `marauder_core/flasher.py`

### 1.1 What to reuse (do not reinvent)
- `_run_stream(argv, on_line)` — the streamed-subprocess runner (kills child on UI close). **:104**
- `esptool_argv(*args)` — `[sys.executable, "-m", "esptool", *args]`. **:93**
- `detect_chip(port, on_line)` — returns `"esp32" | "esp32s3" | ...`. **:140**
- `cache_dir()` — temp working dir. **:241**
- The existing `flash()` `write_flash -z --flash_size detect` invocation as the template. **:251**
- `_BOOTLOADER_0` set — chips whose bootloader is at `0x0` (S3 + RISC-V) vs `0x1000`. **:36**

### 1.2 `suicide_bundle_files(chip, bundle_dir) -> List[Tuple[str, str]]`
A suicide bundle dir (a CI artifact from `Suicide-Marauder/.github/workflows/build.yml`, or a local
build, *after* `host/provision.py` has run into it) contains the COMPLETE flash set named in the
manifest (SPEC §10). Exactly **one** otadata seed is present — `provision.py` emits `boot_app0.bin`
for **FORK** and `otadata_blank.bin` for **GUARDIAN**, never both:

```
bootloader.bin  partitions.bin  app.bin                  # from the build (chip/fixed offsets)
boot_app0.bin        # FORK only  -- the otadata seed (from the build)
otadata_blank.bin    # GUARDIAN only -- the otadata seed (minted 0xFF by provision.py)
guardcfg.bin                                             # minted by provision.py per-device
bundle.json          # the manifest: {"variant","chip","files":[{"file","offset","offset_hex"}]}
```

`suicide_bundle_files()` does **not** decide which otadata seed to write — it simply iterates
`manifest["files"]`, which `provision.py` already populated with the single correct seed for the
bundle's variant. This keeps the flasher and the provisioner in lockstep (one source of truth).

Implementation:

```python
def suicide_bundle_files(chip: str, bundle_dir: str) -> List[Tuple[str, str]]:
    """Return ordered [(offset, abspath)] pairs for a suicide bundle, offsets from bundle.json.

    Consumes the FULL manifest: every entry in manifest["files"] is written. Offsets are READ FROM
    THE MANIFEST (which provision.py derived from the partition CSV) — we do NOT hardcode
    nvs/otadata offsets (SPEC §2: Marauder enlarges nvs, otadata is 0xe000 not 0xd000). The manifest
    already contains exactly ONE otadata seed for its variant (FORK -> boot_app0.bin; GUARDIAN ->
    otadata_blank.bin), so we never pick between them here. Only the bootloader offset is
    chip-derived (0x0 on S3/RISC-V, else 0x1000) and we sanity-check it against the manifest.
    """
    with open(os.path.join(bundle_dir, "bundle.json")) as f:
        manifest = json.load(f)
    bl_off = "0x0" if chip in _BOOTLOADER_0 else "0x1000"
    pairs: List[Tuple[str, str]] = []
    seeds = []                                # track otadata seeds to assert exactly one
    for entry in manifest["files"]:           # schema: {"files":[{"file","offset","offset_hex"},...]}
        path = os.path.join(bundle_dir, entry["file"])
        if not os.path.isfile(path):
            raise FileNotFoundError(f"bundle missing {entry['file']}")
        # offset is stored as an int; offset_hex is the esptool-ready string. Prefer offset_hex,
        # but fall back to formatting the int so older/int-only manifests still work.
        off = entry.get("offset_hex") or (entry["offset"] if isinstance(entry["offset"], str)
                                          else hex(entry["offset"]))
        if entry["file"] == "bootloader.bin" and off.lower() not in (bl_off, "0x0", "0x1000"):
            raise ValueError(f"bootloader offset {off} disagrees with chip {chip} ({bl_off})")
        if entry["file"] in ("boot_app0.bin", "otadata_blank.bin"):
            seeds.append(entry["file"])
        pairs.append((off, path))
    # Exactly one otadata seed must be present (mirrors provision.py's no-collision invariant).
    if len(seeds) != 1:
        raise ValueError(f"expected exactly one otadata seed in the bundle, found {seeds!r}")
    # canonical order: bootloader, partitions, boot_app0, app, guardcfg, otadata_blank
    order = {"bootloader.bin":0,"partitions.bin":1,"boot_app0.bin":2,"app.bin":3,
             "guardcfg.bin":4,"otadata_blank.bin":5}
    pairs.sort(key=lambda p: order.get(os.path.basename(p[1]), 99))
    return pairs
```

### 1.3 `flash_suicide(port, chip, bundle, on_line, baud=921600) -> int`
Builds **one** `write_flash` pair list and reuses the exact same flags as `flash()`:

```python
def flash_suicide(port: str, chip: str, bundle: str, on_line: Line, baud: int = 921600) -> int:
    pairs = suicide_bundle_files(chip, bundle)
    files: List[str] = []
    for off, path in pairs:
        files += [off, path]
    argv = esptool_argv("--chip", chip, "--port", port, "--baud", str(baud),
                        "--before", "default_reset", "--after", "hard_reset",
                        "write_flash", "-z", "--flash_size", "detect", *files)
    on_line("[suicide] writing full bundle from manifest (bootloader+partitions+app+otadata seed+guardcfg)")
    return _run_stream(argv, on_line)
```

Notes:
- The pair list is whatever `suicide_bundle_files()` returns, i.e. **every** entry in
  `manifest["files"]`. The set always contains the four build images (bootloader/partitions/app +
  the variant's single otadata seed) plus `guardcfg.bin`. We never branch on variant here — the
  manifest already encodes it (FORK → `boot_app0.bin`; GUARDIAN → `otadata_blank.bin`).
- `-z` (compress) and `--flash_size detect` are kept verbatim — the same boot-loop fix documented
  in `flash()` (**:268–272**) applies.
- `guardcfg.bin` is sized to the `guardcfg` partition and written at the `guardcfg` NVS offset taken
  from the manifest. The otadata seed is written at the otadata offset (also from the manifest):
  FORK's `boot_app0.bin` boots `app0`; GUARDIAN's `otadata_blank.bin` (`0x2000` of `0xFF`) forces
  first boot into the factory Guardian gate.
- This function never sees a plaintext password — `guardcfg.bin` is already a hashed NVS image.

---

## 2. `gui_qt/app.py` — `FlasherDialog` (class at **:220**)

### 2.1 New widgets (built in `__init__`, after the existing `arow`/baud row at **:270–277**)
A single gating checkbox plus a hidden sub-panel:

- `self.suicide = QCheckBox("Suicide (owner-only duress build)")` — **unchecked by default**.
  `stateChanged` → `self._toggle_suicide()` which shows/hides `self.suicide_box` (a `QGroupBox`).
- Inside `self.suicide_box` (`QFormLayout`), hidden until the checkbox is on:
  - `self.pw = QLineEdit(); self.pw.setEchoMode(QLineEdit.Password)` — **password** (host-hashed; see §3).
  - `self.pw2 = QLineEdit(...Password)` — confirm; refuse to flash if they differ.
  - `self.arm_pin = QSpinBox()` (range 0–48) — dead-man **arm pin** (default from SPEC §7 per chip).
  - `self.arm_level = QComboBox()` items `["HIGH (1)", "LOW (0)"]` — **arm level**.
  - `self.deadman = QCheckBox("Dead-man: cut/missing switch wipes when armed")` — default checked.
  - `self.armed = QCheckBox("Arm now (default OFF / DISARMED)")` — default **unchecked**; a tooltip
    spells out that a disarmed board can never wipe.
  - `self.max_att = QSpinBox()` (range 1–10, default 2).
  - The variant combo (`self.variant`, **:262**) now also offers the **suicide build for the
    detected chip** when the box is checked (filter on the suicide bundle naming / a local bundle dir
    chosen via `self._browse`-style picker).

### 2.2 The SEPARATE T2 checkbox (must be its own control, with a blocking warning)
- `self.t2 = QCheckBox("Flash Encryption + Secure Boot (T2 — IRREVERSIBLE eFuse)")` — its **own**
  checkbox, distinct from the Suicide checkbox.
- On `toggled(True)`, immediately raise a **blocking** modal:
  ```python
  def _confirm_t2(self, on):
      if not on:
          return
      ok = QMessageBox.warning(
          self, "IRREVERSIBLE — T2",
          "T2 burns eFuses to enable Secure Boot v2 + Flash Encryption.\n\n"
          "• This is PERMANENT and cannot be undone on this chip.\n"
          "• The board can no longer be reflashed past the gate.\n"
          "• A subsequent brick is UNRECOVERABLE.\n\n"
          "Only proceed on a board you own and intend to make unrecoverable.\n"
          "Type-to-confirm is required in the next step.\n\nContinue?",
          QMessageBox.Yes | QMessageBox.No, QMessageBox.No)
      if ok != QMessageBox.Yes:
          self.t2.setChecked(False)          # revert; nothing is armed silently
  ```
  Connect with `self.t2.toggled.connect(self._confirm_t2)`. Require a second type-to-confirm
  (`QInputDialog.getText` expecting the literal word `IRREVERSIBLE`) in `_flash()` before any eFuse
  step is allowed.

### 2.3 `_flash()` changes (method at **:363**)
Capture the new widget values on the GUI thread (the existing code already captures values before
spawning the worker — preserve that pattern, **:374–378**). Then:

```python
if self.suicide.isChecked():
    pw  = self.pw.text();  pw2 = self.pw2.text()
    if pw != pw2 or not pw:
        QMessageBox.warning(self, "Password", "Suicide build needs a matching password."); return
    # ---- host-side hashing (NEVER store/log/argv the plaintext) ----
    from marauder_core import provision   # re-exported wrapper around Suicide-Marauder/host/provision.py
    bundle = provision.build_bundle(
        out_dir=cache_or_chosen_dir, chip=chip,
        password=pw,                       # consumed + zeroized inside build_bundle
        arm_pin=self.arm_pin.value(),
        arm_level=(1 if self.arm_level.currentIndex()==0 else 0),
        deadman=int(self.deadman.isChecked()),
        armed=int(self.armed.isChecked()),
        max_attempts=self.max_att.value(),
        brick=int(self.t2.isChecked()),    # T1 default 0; T2 default 1
        tier=("T2" if self.t2.isChecked() else "T1"),
    )
    # zeroize our local copies immediately
    pw = pw2 = None
    rc = flasher.flash_suicide(port, chip, bundle, self._log, baud=baud)
    ...
```

- `provision.build_bundle(...)` (host-side) maps onto `provision.main()`'s flow: it hashes with
  PBKDF2-HMAC-SHA256, writes `guardcfg.bin` via `nvs_partition_gen`, writes `bundle.json` (the
  COMPLETE flash manifest with the chip-derived bootloader offset and the variant's single otadata
  seed), and **zeroizes the password bytearray** before returning the bundle dir. The GUI passes the
  detected `chip` and the `variant` (default `fork`); for GUARDIAN it also mints `otadata_blank.bin`.
  The GUI never writes the plaintext anywhere.
- If `self.t2.isChecked()`, after a successful `flash_suicide`, run the eFuse/Secure-Boot steps
  (separate `espefuse`/`espsecure` invocations through `_run_stream`) **only** after the
  type-to-confirm passed.
- Unchecked Suicide box → existing `flash()` path is completely unchanged (**:381–397**).

### 2.4 Confirmation copy
The existing confirm at **:372** (`"Flash {mode} via {port}?"`) gains, when suicide is on:
`"This flashes an OWNER-ONLY duress build. A correct password always boots; a disarmed board never
wipes. Continue?"`. T2 keeps its own separate blocking warning (§2.2).

---

## 3. Host-side hashing via `provision.py`

- The GUI imports the Suicide-Marauder repo's `host/provision.py` (re-exported as
  `marauder_core.provision` so the import is stable). Add the Suicide-Marauder repo path to
  `sys.path`, or vendor `provision.py` + `nvs_partition_gen` into `marauder_core/suicide/`.
- `provision.build_bundle(...)` is the single entry point the GUI calls. Contract (SPEC §10):
  - inputs: `password` (str, consumed), `arm_pin`, `arm_level`, `arm_pull`, `max_attempts`,
    `deadman`, `armed`, `wipe_*`, `brick`, `kdf_iter`, `chip`, `variant` (default `fork`), `out_dir`,
    `build_dir` (where the build artifacts live). It enforces the SPEC §4.1 clamps: `max_attempts`
    must be ≥ 1, and the arm pull/level pair must be fail-safe (reject `level1+pullup`, `level0+
    pulldown`) — the same checks `validate_args` performs for the CLI.
  - derives `salt = os.urandom(16)`, `pwhash = hashlib.pbkdf2_hmac('sha256', pw, salt, iter, 32)`.
  - emits `guardcfg.bin` (NVS image, namespaces `sgate` / `sgate_rt`, keys per SPEC §4) and
    `bundle.json` (the COMPLETE flash manifest). For GUARDIAN it also mints `otadata_blank.bin`; for
    FORK the otadata seed is the build's `boot_app0.bin` (referenced by the manifest, not minted).
    The manifest's bootloader offset is chip-derived (0x0 on S3/RISC-V, else 0x1000) and the
    guardcfg/otadata offsets are read from the partition CSV.
  - **zeroizes** the password `bytearray` before return; never logs it.
- `requirements.txt`: add `esp-idf-nvs-partition-gen` (NOT bundled with esptool — confirmed in
  RESEARCH-DIGEST), or vendor the Apache-2.0 `nvs_partition_gen.py`. No new crypto dep (stdlib
  `hashlib` PBKDF2).

---

## 4. Tooltips-everywhere sweep (SPEC §12)

Tooltip copy lives in **one place per front-end** so it stays consistent and auditable.

### 4.1 Qt (`gui_qt/app.py`) — central `TIPS` dict, extend `_cmd_tooltip()` (**:42**)
- Add a module-level dict near `_cmd_tooltip`:
  ```python
  TIPS = {
      "port": "Serial port of the board (e.g. COM5 or /dev/ttyUSB0).",
      "detect_chip": "Probe the connected board and identify the ESP32 chip family.",
      "mode_app": "Update only the application at 0x10000 — keeps bootloader/partitions.",
      "mode_full": "Write bootloader + partitions + boot_app0 + app — for a blank board.",
      "src_dl": "Download the latest official Marauder release for the detected chip.",
      "src_local": "Flash a .bin you already have on disk.",
      "variant": "Which firmware build to flash. With Suicide on, this lists the suicide bundle.",
      "baud": "Serial speed for flashing. 921600 is fastest; drop to 115200 if it fails.",
      "flash_btn": "Write the selected firmware to the board. Do not unplug during a flash.",
      "erase": "Erase the ENTIRE flash chip. Wipes any installed firmware and data.",
      # ---- suicide sub-panel ----
      "suicide": "Owner-only duress build: a correct password always boots; a disarmed board "
                 "can NEVER wipe. Read docs/SAFETY.md.",
      "pw": "Boot password (hashed host-side with PBKDF2; never stored or logged in plaintext).",
      "arm_pin": "Dead-man GPIO. The armed switch drives it to the arm level; a cut wire reads NOT-ARMED.",
      "arm_level": "Logic level that means ARMED (HIGH by default).",
      "deadman": "When armed, a cut/missing arming switch triggers a wipe at boot.",
      "armed": "Master arm. DEFAULT OFF. A disarmed board is physically incapable of wiping.",
      "max_att": "Wrong-password attempts before wipe (default 2). Counter survives power-cycles.",
      "t2": "IRREVERSIBLE: burns eFuses for Secure Boot v2 + Flash Encryption. Cannot be undone.",
  }
  ```
- Attach in `FlasherDialog.__init__` after each widget is created:
  `self.flash_btn.setToolTip(TIPS["flash_btn"])`, etc. Sweep **every** interactive widget across the
  whole app (sidebar command buttons already use `_cmd_tooltip`; extend to checkboxes, radios,
  combos, line edits, menu `QAction`s, and table `QHeaderView` sections).
- `_cmd_tooltip()` stays the source for command buttons; `TIPS` covers everything else. One audit
  point each.

### 4.2 Tk (`gui/flasher_window.py`, `gui/app.py`) — add a `Tooltip` helper
Tk has no native tooltip. Add a tiny helper (one place, e.g. `gui/_tooltip.py`):

```python
import tkinter as tk

class Tooltip:
    """Hover help for any Tk widget. Reuses the same copy strings as the Qt TIPS dict."""
    def __init__(self, widget, text, delay=500):
        self.widget, self.text, self.delay = widget, text, delay
        self._id = None; self._tip = None
        widget.bind("<Enter>", self._schedule); widget.bind("<Leave>", self._hide)
        widget.bind("<ButtonPress>", self._hide)
    def _schedule(self, _e=None):
        self._id = self.widget.after(self.delay, self._show)
    def _show(self):
        if self._tip: return
        x = self.widget.winfo_rootx() + 12; y = self.widget.winfo_rooty() + self.widget.winfo_height() + 4
        self._tip = tk.Toplevel(self.widget); self._tip.wm_overrideredirect(True)
        self._tip.wm_geometry(f"+{x}+{y}")
        tk.Label(self._tip, text=self.text, justify="left", background="#11160f",
                 foreground="#c8f7c5", relief="solid", borderwidth=1, padx=6, pady=3,
                 wraplength=320).pack()
    def _hide(self, _e=None):
        if self._id: self.widget.after_cancel(self._id); self._id = None
        if self._tip: self._tip.destroy(); self._tip = None
```
Share the copy with Qt by importing the same `TIPS` dict (move it to a neutral module both can
import, e.g. `marauder_core/tips.py`). Attach `Tooltip(widget, TIPS[key])` on every interactive Tk
widget in the flasher window + the main app, including the new Suicide sub-panel mirror.

### 4.3 Textual TUI (`tui/app.py`) — native `tooltip=`
Textual widgets accept a `tooltip=` keyword (or `.tooltip` property). Set it on every `Button`,
`Input`, `Select`, `Checkbox`, etc. (the flasher screen builds these at **:85–95**), using the same
`TIPS` strings:
```python
yield Button("Detect chip", id="detect", tooltip=TIPS["detect_chip"])
yield Button("Flash app", id="flash_app", variant="success", tooltip=TIPS["mode_app"])
```
Add the Suicide sub-panel mirror (a collapsible container revealed by a `Checkbox("Suicide", ...)`)
with `tooltip=` on each field, and the separate T2 `Checkbox` with a blocking `ModalScreen` warning.

---

## 5. Test / acceptance checklist

- [ ] Suicide checkbox **off** → byte-for-byte the current flash path (regression: existing tests pass).
- [ ] Suicide checkbox **on** + matching password → `provision.build_bundle` runs host-side, no
      plaintext password appears in any log line, `flash_suicide` writes the full pair list with
      offsets read from `bundle.json`.
- [ ] Mismatched / empty password → blocked before any subprocess starts.
- [ ] `max_attempts < 1` or a non-fail-safe arm pair (`level1+pullup`, `level0+pulldown`) → rejected
      by `provision.build_bundle` / `validate_args` before any image is written (SPEC §4.1).
- [ ] FORK bundle manifest lists `boot_app0.bin` at the otadata offset (and NOT `otadata_blank.bin`);
      GUARDIAN lists `otadata_blank.bin` there (and NOT `boot_app0.bin`). Exactly one seed either way.
- [ ] `suicide_bundle_files` iterates the FULL manifest, uses `offset_hex`, and raises if the bundle
      does not contain exactly one otadata seed.
- [ ] T2 checkbox → blocking warning + type-to-confirm `IRREVERSIBLE`; declining reverts the checkbox.
- [ ] `suicide_bundle_files` raises on a missing bundle file or a bootloader-offset/chip mismatch.
- [ ] All three front-ends: every interactive widget has a tooltip sourced from the shared `TIPS`.
- [ ] grep the repo for the plaintext password variable — it must never reach `on_line`, a file, or argv.

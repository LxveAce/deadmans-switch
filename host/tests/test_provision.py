# test_provision.py -- host-side unit tests for provision.py.
#
# These cover the security- and parity-critical PURE functions of the provisioner: partition-table
# parsing, the three-way bootloader offset, password validation (the firmware-parity clamps),
# argument validation (fail-safe arming + fail-closed clamps), the PBKDF2 host<->device parity
# vector, the NVS row schema, and the "exactly one otadata seed" bundle invariant.
#
# Stdlib + pytest only. NO board, NO esp-idf-nvs-partition-gen, NO network -- fully runnable in CI.
# Source of truth for the contract constants is docs/SPEC.md sec 4 / firmware GateConfig.h; source of
# truth for the serial/`unlock ` normalization mirrored by validate_password is
# firmware/bootgate/GateInput_serial.cpp.

import hashlib
import os

import pytest

import provision


HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(os.path.dirname(HERE))  # tests -> host -> repo root
PARTS_DIR = os.path.join(REPO_ROOT, "firmware", "partitions")


def _make_args(**overrides):
    """Build a fully-populated args namespace via the real parser, then apply overrides.

    --partitions is required by the parser; callers that don't exercise it pass a dummy path.
    Overrides use the dest name (e.g. arm_level=1); the value is stringified onto argv so argparse
    type/choice validation runs exactly as in production.
    """
    argv = ["--partitions", overrides.pop("partitions", "dummy.csv")]
    for key, val in overrides.items():
        argv.extend(["--" + key.replace("_", "-"), str(val)])
    return provision.build_arg_parser().parse_args(argv)


# --------------------------------------------------------------------------------------------------
# Canonical schema constants MUST match firmware GateConfig.h / docs/SPEC.md sec 4 (host<->device
# parity). A silent drift here would make correct passwords fail on-device, so pin them.
# --------------------------------------------------------------------------------------------------

def test_canonical_schema_constants():
    assert provision.NVS_NAMESPACE == "sgate"
    assert provision.CFG_VERSION == 1
    assert provision.SALT_LEN == 16
    assert provision.KDF_DKLEN == 32
    assert provision.DEFAULT_KDF_ITER == 10000
    assert provision.SUICIDE_PW_MAX_BYTES == 63
    assert provision.OTADATA_FILL_BYTE == 0xFF
    assert provision.PARTITIONS_OFFSET == 0x8000
    assert provision.APP_OFFSET == 0x10000
    assert provision.GUARDCFG_PART == "guardcfg"
    assert provision.OTADATA_PART == "otadata"


# --------------------------------------------------------------------------------------------------
# _parse_size_token -- hex / decimal / K / M / empty / invalid
# --------------------------------------------------------------------------------------------------

@pytest.mark.parametrize("tok,expected", [
    ("0x1F0000", 0x1F0000),
    ("0x3000", 0x3000),
    ("8192", 8192),
    ("8K", 8 * 1024),
    ("8k", 8 * 1024),
    ("1M", 1024 * 1024),
    ("1m", 1024 * 1024),
    ("", None),
    ("   ", None),
    (None, None),
])
def test_parse_size_token(tok, expected):
    assert provision._parse_size_token(tok) == expected


def test_parse_size_token_invalid_raises():
    with pytest.raises(provision.ProvisionError):
        provision._parse_size_token("not-a-number")


# --------------------------------------------------------------------------------------------------
# parse_partitions_csv against ALL FOUR shipped tables (explicit-offset path)
# --------------------------------------------------------------------------------------------------

# name -> (guardcfg offset, guardcfg size, otadata offset). Verified against the committed CSVs.
_SHIPPED = {
    "suicide_4MB.csv":          (0x1F0000, 0x3000, 0xE000),
    "suicide_8MB.csv":          (0x3D0000, 0x4000, 0xE000),
    "suicide_16MB.csv":         (0x3D0000, 0x10000, 0xE000),
    "suicide_guardian_16MB.csv": (0x310000, 0x10000, 0xE000),
}


@pytest.mark.parametrize("csv_name", sorted(_SHIPPED))
def test_parse_shipped_csv(csv_name):
    path = os.path.join(PARTS_DIR, csv_name)
    assert os.path.isfile(path), "missing shipped partition table %s" % path
    parts = provision.parse_partitions_csv(path)

    exp_off, exp_size, exp_ota = _SHIPPED[csv_name]

    gc = provision.require_partition(parts, "guardcfg")
    assert gc["subtype"] == "nvs"
    assert gc["offset"] == exp_off
    assert gc["size"] == exp_size
    # SPEC/provision invariant: guardcfg must be a read/write NVS partition (>= 0x3000).
    assert gc["size"] >= 0x3000

    ota = provision.require_partition(parts, "otadata")
    assert ota["offset"] == exp_ota

    # Marauder's otadata is at 0xe000, NOT the stock 0xd000 -- the whole reason offsets are READ.
    assert ota["offset"] == 0xE000


def test_parse_guardian_has_factory_and_ota0():
    parts = provision.parse_partitions_csv(os.path.join(PARTS_DIR, "suicide_guardian_16MB.csv"))
    factory = provision.require_partition(parts, "factory")
    ota0 = provision.require_partition(parts, "ota_0")
    assert factory["offset"] == 0x10000
    assert ota0["offset"] == 0x110000


def test_parse_missing_file_raises():
    with pytest.raises(provision.ProvisionError):
        provision.parse_partitions_csv(os.path.join(PARTS_DIR, "does_not_exist.csv"))


# --------------------------------------------------------------------------------------------------
# parse_partitions_csv auto-offset branch (blank offset column -> cursor + alignment)
# --------------------------------------------------------------------------------------------------

def test_parse_auto_offsets(tmp_path):
    csv = tmp_path / "auto.csv"
    csv.write_text(
        "# Name, Type, SubType, Offset, Size, Flags\n"
        "nvs,      data, nvs,   0x9000, 0x5000,\n"
        "otadata,  data, ota,   ,       0x2000,\n"   # blank -> follows nvs at 0xE000
        "app0,     app,  ota_0, ,       0x1E0000,\n"  # blank -> app aligns to 0x10000
        "guardcfg, data, nvs,   ,       0x3000,\n",   # blank -> data aligns to 0x1000
        encoding="utf-8",
    )
    parts = provision.parse_partitions_csv(str(csv))
    assert parts["nvs"]["offset"] == 0x9000
    assert parts["otadata"]["offset"] == 0xE000   # 0x9000 + 0x5000
    assert parts["app0"]["offset"] == 0x10000     # 0xE000 + 0x2000 already 64K-aligned
    assert parts["guardcfg"]["offset"] == 0x1F0000  # 0x10000 + 0x1E0000


def test_parse_auto_offset_app_alignment(tmp_path):
    # A misaligned cursor must be rounded UP to the 0x10000 app boundary (exercise the align branch).
    csv = tmp_path / "align.csv"
    csv.write_text(
        "nvs,   data, nvs,   0x9000, 0x5000,\n"
        "ota,   data, ota,   ,       0x2000,\n"   # -> 0xE000, cursor 0x10000
        "app0,  app,  ota_0, ,       0x1000,\n"   # -> 0x10000, cursor 0x11000 (misaligned)
        "app1,  app,  ota_1, ,       0x1000,\n",  # -> aligns up to 0x20000
        encoding="utf-8",
    )
    parts = provision.parse_partitions_csv(str(csv))
    assert parts["app0"]["offset"] == 0x10000
    assert parts["app1"]["offset"] == 0x20000


def test_parse_empty_csv_raises(tmp_path):
    csv = tmp_path / "empty.csv"
    csv.write_text("# only a comment\n\n", encoding="utf-8")
    with pytest.raises(provision.ProvisionError):
        provision.parse_partitions_csv(str(csv))


# --------------------------------------------------------------------------------------------------
# require_partition error paths
# --------------------------------------------------------------------------------------------------

def test_require_partition_missing():
    with pytest.raises(provision.ProvisionError):
        provision.require_partition({}, "guardcfg")


def test_require_partition_no_size(tmp_path):
    csv = tmp_path / "nosize.csv"
    csv.write_text("guardcfg, data, nvs, 0x1F0000,\n", encoding="utf-8")  # no size column
    parts = provision.parse_partitions_csv(str(csv))
    with pytest.raises(provision.ProvisionError):
        provision.require_partition(parts, "guardcfg")


# --------------------------------------------------------------------------------------------------
# bootloader_offset -- three-way branch (SPEC sec 2)
# --------------------------------------------------------------------------------------------------

@pytest.mark.parametrize("chip,expected", [
    ("esp32", 0x1000),
    ("esp32s2", 0x1000),
    ("esp32s3", 0x0),
    ("esp32c3", 0x0),
    ("esp32c6", 0x0),
    ("esp32h2", 0x0),
    ("esp32c5", 0x2000),
    ("esp32p4", 0x2000),
    ("esp32h4", 0x2000),
    ("unknown-chip", 0x1000),  # conservative classic default
])
def test_bootloader_offset(chip, expected):
    assert provision.bootloader_offset(chip) == expected


# --------------------------------------------------------------------------------------------------
# validate_password -- every firmware-parity clamp (GateInput_serial.cpp normalization)
# --------------------------------------------------------------------------------------------------

def test_validate_password_ok():
    assert provision.validate_password(b"correct horse battery") is None
    assert provision.validate_password(b"a" * provision.SUICIDE_PW_MAX_BYTES) is None
    # "unlock" is only reserved as a leading keyword; embedded/other use is fine.
    assert provision.validate_password(b"myunlockpass") is None
    assert provision.validate_password(b"unlocked") is None  # no space after "unlock"


@pytest.mark.parametrize("pw", [
    b"",                                       # empty
    b"a" * (provision.SUICIDE_PW_MAX_BYTES + 1),  # 64 bytes -> clamped on-device -> never matches
    b" leading",                               # leading space (serial strips it)
    b"trailing ",                              # trailing space
    b"\tleadtab",                              # leading tab
    b"trailtab\t",                             # trailing tab
    b"unlock secret",                          # reserved serial keyword prefix
    b"UNLOCK secret",                          # case-insensitive keyword
    b"unlock\tsecret",                         # keyword + tab
])
def test_validate_password_rejects(pw):
    with pytest.raises(provision.ProvisionError):
        provision.validate_password(pw)


# --------------------------------------------------------------------------------------------------
# validate_args -- fail-closed clamps + fail-safe arming pairs (SPEC sec 4.1)
# --------------------------------------------------------------------------------------------------

def test_validate_args_defaults_ok():
    # Defaults are the fail-safe pair (arm_level=1 + pulldown) and a sane kdf_iter -> must not raise.
    provision.validate_args(_make_args())


@pytest.mark.parametrize("kdf_iter", [1, 2000, 10000, 0xFFFFFFFF])
def test_validate_args_kdf_iter_in_range(kdf_iter):
    provision.validate_args(_make_args(kdf_iter=kdf_iter))  # must not raise


def test_validate_args_kdf_iter_zero_rejected():
    with pytest.raises(provision.ProvisionError):
        provision.validate_args(_make_args(kdf_iter=0))


def test_validate_args_kdf_iter_over_u32_rejected():
    with pytest.raises(provision.ProvisionError):
        provision.validate_args(_make_args(kdf_iter=0x100000000))  # 0xFFFFFFFF + 1


def test_validate_args_max_att_zero_rejected():
    # max_att MUST be >= 1: a stored 0 would arm a wipe with zero failed attempts.
    with pytest.raises(provision.ProvisionError):
        provision.validate_args(_make_args(max_att=0))


def test_validate_args_max_att_one_ok():
    provision.validate_args(_make_args(max_att=1))


@pytest.mark.parametrize("arm_level,arm_pull", [
    (1, 1),  # ARMED=HIGH + pullup   -> idles HIGH/ARMED  (a cut wire reads ARMED) -> UNSAFE
    (0, 2),  # ARMED=LOW  + pulldown -> idles LOW/ARMED    (a cut wire reads ARMED) -> UNSAFE
])
def test_validate_args_non_fail_safe_pairs_rejected(arm_level, arm_pull):
    with pytest.raises(provision.ProvisionError):
        provision.validate_args(_make_args(arm_level=arm_level, arm_pull=arm_pull))


@pytest.mark.parametrize("arm_level,arm_pull", [
    (1, 2),  # ARMED=HIGH + pulldown -> idles LOW/NOT-ARMED   (fail-safe)
    (0, 1),  # ARMED=LOW  + pullup   -> idles HIGH/NOT-ARMED  (fail-safe)
])
def test_validate_args_fail_safe_pairs_ok(arm_level, arm_pull):
    provision.validate_args(_make_args(arm_level=arm_level, arm_pull=arm_pull))  # must not raise


# --------------------------------------------------------------------------------------------------
# derive_pwhash -- PBKDF2-HMAC-SHA256 host<->device parity (GateCrypto.derive)
# --------------------------------------------------------------------------------------------------

def test_derive_pwhash_known_vector():
    # Pinned vector: PBKDF2-HMAC-SHA256("password", "saltsaltsaltsalt", 10000, 32).
    # A change to algo/dklen/iteration handling would break host<->device parity and flip this.
    pw = bytearray(b"password")
    salt = b"saltsaltsaltsalt"
    expected = "fc706db7b67fee9d02cd1bd237507e297aca36c92f46db35516c3ad73293154a"
    out = provision.derive_pwhash(pw, salt, 10000, provision.KDF_DKLEN)
    assert out.hex() == expected
    assert len(out) == provision.KDF_DKLEN


def test_derive_pwhash_matches_stdlib():
    pw = bytearray(b"another-pass")
    salt = os.urandom(provision.SALT_LEN)
    ours = provision.derive_pwhash(pw, salt, 4096, provision.KDF_DKLEN)
    ref = hashlib.pbkdf2_hmac("sha256", b"another-pass", salt, 4096, provision.KDF_DKLEN)
    assert ours == ref


def test_derive_pwhash_does_not_mutate_source_buffer():
    # The device zeroizes plaintext separately; derive must not disturb the caller's buffer.
    pw = bytearray(b"keepme")
    provision.derive_pwhash(pw, b"saltsaltsaltsalt", 1000, provision.KDF_DKLEN)
    assert bytes(pw) == b"keepme"


@pytest.mark.parametrize("bad_iter", [0, 0x100000000])
def test_derive_pwhash_iter_out_of_range(bad_iter):
    with pytest.raises(provision.ProvisionError):
        provision.derive_pwhash(bytearray(b"pw"), b"saltsaltsaltsalt", bad_iter, provision.KDF_DKLEN)


# --------------------------------------------------------------------------------------------------
# build_nvs_rows -- canonical namespace + key/type schema (SPEC sec 4)
# --------------------------------------------------------------------------------------------------

def test_build_nvs_rows_schema():
    args = _make_args(kdf_iter=12345)
    salt = bytes(range(provision.SALT_LEN))
    pwhash = bytes(range(provision.KDF_DKLEN))
    rows = provision.build_nvs_rows(args, salt, pwhash)

    # First row MUST be the namespace declaration for nvs_partition_gen.
    assert rows[0] == (provision.NVS_NAMESPACE, "namespace", "", "")

    by_key = {r[0]: r for r in rows}
    assert by_key["cfg_ver"] == ("cfg_ver", "data", "u8", str(provision.CFG_VERSION))
    assert by_key["salt"] == ("salt", "data", "hex2bin", salt.hex())
    assert by_key["pwhash"] == ("pwhash", "data", "hex2bin", pwhash.hex())
    assert by_key["kdf_iter"] == ("kdf_iter", "data", "u32", "12345")
    assert by_key["kdf_dklen"] == ("kdf_dklen", "data", "u8", str(provision.KDF_DKLEN))
    # The runtime namespace (sgate_rt) is created on-device, never written by the host.
    assert not any(r[0] == "sgate_rt" for r in rows)


# --------------------------------------------------------------------------------------------------
# build_manifest_files -- "exactly one otadata seed" invariant (SPEC sec 10), FORK + GUARDIAN
# --------------------------------------------------------------------------------------------------

def _manifest_for(csv_name, variant, chip, out_dir):
    path = os.path.join(PARTS_DIR, csv_name)
    args = _make_args(partitions=path, variant=variant, chip=chip, out=str(out_dir))
    parts = provision.parse_partitions_csv(path)
    guardcfg = provision.require_partition(parts, provision.GUARDCFG_PART)
    otadata = provision.require_partition(parts, provision.OTADATA_PART)
    return provision.build_manifest_files(args, parts, guardcfg, otadata), otadata["offset"]


def test_manifest_fork_single_otadata_seed(tmp_path):
    (files, warnings), otadata_off = _manifest_for("suicide_4MB.csv", "fork", "esp32", tmp_path)
    by_name = {f["file"]: f for f in files}

    # Exactly ONE image lands on the otadata offset (no collision).
    on_otadata = [f for f in files if f["offset"] == otadata_off]
    assert len(on_otadata) == 1
    assert on_otadata[0]["file"] == "boot_app0.bin"

    # Fork => single app at the fixed 0x10000; classic bootloader at 0x1000; no guardian otadata blob.
    assert by_name["bootloader.bin"]["offset"] == 0x1000
    assert by_name["partitions.bin"]["offset"] == provision.PARTITIONS_OFFSET
    assert by_name["app.bin"]["offset"] == provision.APP_OFFSET
    assert "otadata_blank.bin" not in by_name

    gc = by_name["guardcfg.bin"]
    assert gc["offset"] == 0x1F0000 and gc["partition"] == "guardcfg" and gc["size"] == 0x3000

    # No --build-dir given -> every build artifact is flagged absent (manifest still complete).
    assert warnings


def test_manifest_guardian_single_otadata_seed(tmp_path):
    (files, _warn), otadata_off = _manifest_for(
        "suicide_guardian_16MB.csv", "guardian", "esp32", tmp_path)
    by_name = {f["file"]: f for f in files}

    on_otadata = [f for f in files if f["offset"] == otadata_off]
    assert len(on_otadata) == 1
    assert on_otadata[0]["file"] == "otadata_blank.bin"  # all-0xFF seed -> first boot = factory

    # Guardian => TWO app images: factory Guardian gate + unmodified Marauder in ota_0.
    assert by_name["guardian.bin"]["offset"] == 0x10000
    assert by_name["guardian.bin"]["partition"] == "factory"
    assert by_name["marauder.bin"]["offset"] == 0x110000
    assert by_name["marauder.bin"]["partition"] == "ota_0"
    assert "boot_app0.bin" not in by_name


def test_manifest_bootloader_offset_by_chip(tmp_path):
    # The bootloader offset in the manifest tracks the chip (0x0 on s3), proving it is chip-derived.
    (files, _warn), _off = _manifest_for("suicide_8MB.csv", "fork", "esp32s3", tmp_path)
    by_name = {f["file"]: f for f in files}
    assert by_name["bootloader.bin"]["offset"] == 0x0

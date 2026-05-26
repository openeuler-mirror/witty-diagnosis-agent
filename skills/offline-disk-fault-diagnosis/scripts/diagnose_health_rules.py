#!/usr/bin/env python3
"""
Step 3 helper: Disk health rule evaluation.

For every disk discovered in the log bundle, evaluate the SAS / SATA hard-fault
rules and (when no rule is hit) compute a survival probability based on the
deviation of each numeric SMART indicator. NVMe disks are not covered by the
rule set, so they are reported as "Cannot evaluate" with a recommendation to
run nvme-cli self checks on the live host.

The rules are sourced from references/disk_health_rules.md (kept human-readable
for documentation). The numeric thresholds are mirrored as constants in this
script so a runtime parse of the markdown file is not required.
"""
import os
import sys
import re
import json
import argparse
from collections import OrderedDict

# ---------------------------------------------------------------------------
# Rule constants (mirror of references/disk_health_rules.md)
# ---------------------------------------------------------------------------
SAS_THRESHOLDS = {
    "defect_list_max": 1000,
    "uncorrected_write_max": 50,
    "uncorrected_read_max": 1000,
    "uncorrected_verify_max": 1000,
}

SATA_THRESHOLDS = {
    "reallocated_max": 1000,        # ID 5  RAW
    "pending_max": 1000,            # ID 197 RAW
    "offline_uncorrectable_max": 1000,  # ID 198 RAW
    "power_on_hours_max": 61320,    # ID 9 RAW (~7 years)
    "rate_factor": 1.05,            # ID 1 / ID 7 WORST <= Thresh * 1.05
    "spin_up_factor": 0.30,         # ID 3 VALUE <= 30%*(Default-Thresh)+Thresh
}

WD_VENDOR_TOKENS = ("WD", "WDC", "WESTERN DIGITAL")
WD_SPIN_UP_DEFAULT = 200
OTHER_SPIN_UP_DEFAULT = 100

# Numeric indicators used by the survival probability formula.
# Each entry: name -> (healthy, threshold, is_reverse)
#   is_reverse=False  → "actual越大越差", deviation=(actual-healthy)/(thresh-healthy)
#   is_reverse=True   → "actual越小越差", deviation=(healthy-actual)/(healthy-thresh)
NUMERIC_INDICATORS_FORWARD = (
    "Reallocated_Sector_Ct",
    "Current_Pending_Sector",
    "Offline_Uncorrectable",
    "Power_On_Hours",
    "Elements_in_grown_defect_list",
    "Uncorrected_Write",
    "Uncorrected_Read",
    "Uncorrected_Verify",
)
NUMERIC_INDICATORS_REVERSE = (
    "Raw_Read_Error_Rate",     # WORST
    "Seek_Error_Rate",         # WORST
    "Spin_Up_Time",            # VALUE
)

# Action level mapping (per disk_health_rules.md §3.5):
#   survival == 0%          → Replace immediately (hard rule hit)
#   0% < survival < 30%     → Replace soon
#   30% ≤ survival < 70%    → Increase monitoring
#   survival ≥ 70%          → Keep running
def action_for(survival_prob):
    if survival_prob <= 0.0:
        return "Replace immediately (hard rule hit)"
    if survival_prob < 0.30:
        return "Replace soon"
    if survival_prob < 0.70:
        return "Increase monitoring"
    return "Keep running"


# Per SKILL.md §3.5.2: rule_id → repairable boolean.
# True  = degradation that can be mitigated (cable swap, re-test, monitor)
# False = irreversible media-level damage; the disk must be replaced
RULE_REPAIRABLE_MAP = {
    "SAS-R1":  False,
    "SAS-R2":  False,
    "SAS-R3":  False,
    "SAS-R4":  False,
    "SATA-R1": False,
    "SATA-R2": False,
    "SATA-R3": False,
    "SATA-R4": False,
    "SATA-R5": False,
    "SATA-R6": True,
    "SATA-R7": True,
    "SATA-R8": True,
    "SATA-R9": True,
    "SATA-R10": True,
}

# Chinese short descriptions used to populate failure_rules_hit and
# analysis_reasons in the standardized output object.
RULE_SHORT_DESC = {
    "SAS-R1":  ("Elements in grown defect list", "SAS 增长缺陷扇区数"),
    "SAS-R2":  ("Total uncorrected errors (w/r/v)", "SAS 累计不可纠正错误"),
    "SAS-R3":  ("SMART Health Status", "SMART 健康状态"),
    "SAS-R4":  ("asc=0x5d predictive failure", "asc=0x5d 预测性故障"),
    "SATA-R1": ("SMART Error Log", "SMART 错误日志非空"),
    "SATA-R2": ("overall-health self-assessment", "SMART 自评结果"),
    "SATA-R3": ("Reallocated_Sector_Ct (RAW)", "SMART 5 重映射扇区计数"),
    "SATA-R4": ("Current_Pending_Sector (RAW)", "SMART 197 待定扇区计数"),
    "SATA-R5": ("Offline_Uncorrectable (RAW)", "SMART 198 离线不可纠正扇区"),
    "SATA-R6": ("UDMA_CRC_Error_Count", "SMART 199 UDMA CRC 错误"),
    "SATA-R7": ("Raw_Read_Error_Rate WORST", "SMART 1 读取错误率退化"),
    "SATA-R8": ("Seek_Error_Rate WORST", "SMART 7 寻道错误率退化"),
    "SATA-R9": ("Spin_Up_Time VALUE", "SMART 3 启动速度退化"),
    "SATA-R10": ("Power_On_Hours > 7y", "SMART 9 通电时长超 7 年"),
}


# ---------------------------------------------------------------------------
# File discovery
# ---------------------------------------------------------------------------
def find_files(root_dir, regex):
    matches = []
    pat = re.compile(regex)
    for root, _dirs, files in os.walk(root_dir):
        for f in files:
            if pat.search(f):
                matches.append(os.path.join(root, f))
    return matches


# ---------------------------------------------------------------------------
# Disk record dataclass (use plain dict to stay stdlib-friendly)
# ---------------------------------------------------------------------------
def new_disk_record(slot=None, device=None, interface=None, model=None,
                    serial=None, source_file=None, source_line=None):
    return {
        "slot": slot,
        "device": device,
        "interface": interface,        # "SAS" | "SATA" | "NVMe" | "Unknown"
        "model": model,
        "serial": serial,
        "vendor": None,                # derived
        # Standardized output fields (SKILL.md §3.7) ----------------------
        "vol_id": None,                # filled by attach_volume_map()
        "capacity": None,              # parsed from "User Capacity:" etc.
        "power_on_hours": None,        # explicit int, mirrors SMART attr 9 RAW
        # ----------------------------------------------------------------
        "raw_text": [],                # list of (line_no, line)
        "source_file": source_file,
        "source_line": source_line,    # 1-based line where the section starts
        "fields": OrderedDict(),       # parsed key/value with evidence
        "rule_results": [],            # list of RuleResult
        "survival_prob": None,
        "deviations": OrderedDict(),
        "action_level": None,
        "notes": [],
    }


def new_rule_result(rule_id, description, threshold, actual, hit, evidence,
                    note=None):
    return {
        "rule_id": rule_id,
        "description": description,
        "threshold": threshold,
        "actual": actual,
        "hit": hit,                    # True | False | None (=N/A)
        "evidence": evidence,          # "[abs_path:line]"
        "note": note,
    }


# ---------------------------------------------------------------------------
# smartctl parser (handles SAS and SATA outputs)
# ---------------------------------------------------------------------------
# A new disk section begins at a "smartctl" invocation banner. We do NOT
# split on "=== START OF ... ===" lines because a single smartctl run emits
# several of them (INFORMATION / READ SMART DATA / READ SMART ERROR LOG ...)
# for the same disk.
SECTION_SPLIT_RE = re.compile(r"^smartctl\s+\d", re.MULTILINE)

# SATA attribute table line, e.g.
#   5 Reallocated_Sector_Ct   0x0033   100   100   010    Pre-fail  Always       -       0
SATA_ATTR_RE = re.compile(
    r"^\s*(?P<id>\d+)\s+(?P<name>[A-Za-z_\-0-9/]+)\s+"
    r"0x[0-9a-fA-F]+\s+(?P<value>\d+)\s+(?P<worst>\d+)\s+(?P<thresh>\d+)\s+"
    r"\S+\s+\S+\s+\S+\s+(?P<raw>[\-\w]+)"
)


def detect_interface(section_text):
    # NVMe detection
    if re.search(r"NVMe Log|NVMe Version|/dev/nvme", section_text, re.I):
        return "NVMe"
    # SAS detection (SCSI-style smartctl: "Transport protocol: SAS"
    # or "Vendor:" + "Elements in grown defect list" pattern)
    if re.search(r"Transport protocol:\s*SAS", section_text, re.I) \
            or re.search(r"^\s*Vendor:\s+", section_text, re.MULTILINE) \
            or "Elements in grown defect list" in section_text:
        return "SAS"
    # SATA detection (ATA-style smartctl: SATA/ATA version line, or
    # the ATA SMART attributes table header that doesn't appear in SAS)
    if re.search(r"SATA Version|ATA Version", section_text, re.I) \
            or "Vendor Specific SMART Attributes with Thresholds" in section_text \
            or re.search(r"SMART overall-health self-assessment", section_text):
        return "SATA"
    return "Unknown"


def parse_kv(section_text, key):
    m = re.search(rf"^{re.escape(key)}\s*:\s*(.+)$", section_text, re.MULTILINE)
    return m.group(1).strip() if m else None


def line_of(section_text, substring, base_line=1):
    """Return absolute line number (1-based) of substring within section."""
    for i, line in enumerate(section_text.splitlines(), start=base_line):
        if substring in line:
            return i
    return None


def parse_sata_attributes(section_text, base_line=1):
    """Return dict id -> {name, value, worst, thresh, raw, line}."""
    attrs = {}
    for i, line in enumerate(section_text.splitlines(), start=base_line):
        m = SATA_ATTR_RE.match(line)
        if not m:
            continue
        try:
            attrs[int(m.group("id"))] = {
                "name": m.group("name"),
                "value": int(m.group("value")),
                "worst": int(m.group("worst")),
                "thresh": int(m.group("thresh")),
                "raw_str": m.group("raw"),
                "raw": _safe_int(m.group("raw")),
                "line": i,
            }
        except ValueError:
            continue
    return attrs


def parse_sas_fields(section_text, base_line=1):
    """Extract SAS-specific fields: defect list, uncorrected errors, health."""
    fields = {}

    # Elements in grown defect list
    m = re.search(r"Elements in grown defect list:\s*(\d+)", section_text)
    if m:
        fields["defect_list"] = {
            "value": int(m.group(1)),
            "line": line_of(section_text, m.group(0), base_line),
        }

    # SMART Health Status
    m = re.search(r"SMART Health Status:\s*(.+)", section_text)
    if m:
        fields["health_status"] = {
            "value": m.group(1).strip(),
            "line": line_of(section_text, m.group(0), base_line),
        }

    # "Errors Corrected" table — find the row labelled "Total uncorrected errors"
    # Layout (smartctl):
    #            Errors Corrected by         Total   ...
    #                ECC            rereads  errors  ...
    # write:           0              0         0    ...
    # read:            0              0         0    ...
    # verify:          0              0         0    ...
    for op in ("write", "read", "verify"):
        # Last number on each line is "Total uncorrected errors"
        pat = re.compile(rf"^\s*{op}:\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(\d+)\s*$",
                         re.MULTILINE)
        m = pat.search(section_text)
        if m:
            fields[f"uncorrected_{op}"] = {
                "value": int(m.group(1)),
                "line": line_of(section_text, m.group(0).strip(), base_line),
            }
    return fields


def _safe_int(s):
    if s is None:
        return None
    s = s.replace(",", "").strip()
    if s.isdigit():
        return int(s)
    # SMART RAW values sometimes look like "100 (Min/Max ...)"
    m = re.match(r"-?\d+", s)
    return int(m.group(0)) if m else None


# ---------------------------------------------------------------------------
# Discovery of disk records
# ---------------------------------------------------------------------------
SMART_FILE_PATTERNS = (
    r"^disk_smart\.txt$",
    r"^smart.*\.txt$",
    r"^disk_other_info\.txt$",
)
NVME_FILE_PATTERNS = (
    r"^nvme.*\.txt$",
    r"^es3000.*\.txt$",
    r"^es3000_v2.*\.txt$",
)


def discover_disks(log_dir):
    disks = []

    # 1. smartctl-style files
    for pattern in SMART_FILE_PATTERNS:
        for path in find_files(log_dir, pattern):
            disks.extend(parse_smartctl_file(path))

    # 2. NVMe-only files (best-effort: one disk per file)
    for pattern in NVME_FILE_PATTERNS:
        for path in find_files(log_dir, pattern):
            if any(d["source_file"] == path for d in disks):
                continue
            disks.extend(parse_nvme_file(path))

    return disks


def parse_smartctl_file(path):
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            raw = f.read()
    except OSError:
        return []

    if not raw.strip():
        return []

    # Compute line numbers for each section
    lines = raw.splitlines()
    section_starts = [i for i, ln in enumerate(lines)
                      if SECTION_SPLIT_RE.match(ln)]
    if not section_starts:
        # Single section file
        sections = [(0, raw)]
    else:
        sections = []
        for idx, start_line in enumerate(section_starts):
            end_line = section_starts[idx + 1] if idx + 1 < len(section_starts) \
                       else len(lines)
            text = "\n".join(lines[start_line:end_line])
            sections.append((start_line + 1, text))   # 1-based

    out = []
    for base_line, text in sections:
        rec = build_record_from_section(text, base_line, path)
        if rec is not None:
            out.append(rec)
    return out


def build_record_from_section(text, base_line, path):
    if len(text.strip()) < 20:
        return None

    iface = detect_interface(text)
    rec = new_disk_record(source_file=path, source_line=base_line,
                          interface=iface)

    rec["model"] = parse_kv(text, "Device Model") or \
                   parse_kv(text, "Product") or \
                   parse_kv(text, "Vendor")
    rec["serial"] = parse_kv(text, "Serial Number") or \
                    parse_kv(text, "Serial number")

    # Device path hint — try several patterns commonly emitted by collectors
    for pat in (
        r"smartctl.*?(/dev/\S+)",        # "smartctl -a /dev/sdX"
        r"#\s*(/dev/\S+)",               # "# /dev/sdX"
        r"^Device:\s*(/dev/\S+)",        # "Device: /dev/sdX"
        r"(/dev/(?:sd|nvme|hd|cciss/c)\w+)",  # bare /dev/sdX anywhere
    ):
        m = re.search(pat, text, re.MULTILINE)
        if m:
            rec["device"] = m.group(1).rstrip(":")
            break

    # Slot hint (some collectors prepend "# Slot N" or include "Enclosure")
    m = re.search(r"Slot\s*[#:=]?\s*(\d+)", text)
    if m:
        rec["slot"] = m.group(1)

    # Vendor classification (for WD spin-up default)
    if rec["model"]:
        up = rec["model"].upper()
        for tok in WD_VENDOR_TOKENS:
            if tok in up:
                rec["vendor"] = "WD"
                break
        if rec["vendor"] is None:
            rec["vendor"] = "Other"

    # Capacity (e.g. "User Capacity: 4,000,787,030,016 bytes [4.00 TB]")
    m = re.search(r"User Capacity:\s+[\d,\s]+bytes\s*\[([^\]]+)\]", text)
    if m:
        rec["capacity"] = m.group(1).strip()
    else:
        m = re.search(r"User Capacity:\s+([\d,]+)\s*bytes", text)
        if m:
            try:
                bytes_val = int(m.group(1).replace(",", ""))
                rec["capacity"] = _format_capacity(bytes_val)
            except ValueError:
                pass

    # Parse interface-specific fields
    if iface == "SATA":
        rec["fields"]["smart_attrs"] = parse_sata_attributes(text, base_line)
        rec["fields"]["health"] = parse_kv(text,
            "SMART overall-health self-assessment test result")
        rec["fields"]["health_line"] = line_of(text,
            "SMART overall-health self-assessment test result", base_line)
        # SMART Error Log section: look for "No Errors Logged"
        if re.search(r"No Errors Logged", text):
            rec["fields"]["error_log"] = "No Errors Logged"
        else:
            m = re.search(r"Error \d+ occurred", text)
            rec["fields"]["error_log"] = m.group(0) if m else None
        rec["fields"]["error_log_line"] = (
            line_of(text, "No Errors Logged", base_line)
            or line_of(text, "SMART Error Log Version", base_line)
        )
        # SATA: Power_On_Hours from SMART attr 9 RAW
        attr_9 = rec["fields"]["smart_attrs"].get(9)
        if attr_9 and attr_9.get("raw") is not None:
            rec["power_on_hours"] = attr_9["raw"]

    elif iface == "SAS":
        rec["fields"].update(parse_sas_fields(text, base_line))
        # SAS: "Accumulated power on time, hours:minutes 16502:24"
        # or  "Accumulated power on time [hours]: 16502"
        m = re.search(
            r"Accumulated power on time[^\d]*?(\d+)\s*[:\s]\s*\d+",
            text,
        )
        if m:
            try:
                rec["power_on_hours"] = int(m.group(1))
            except ValueError:
                pass

    elif iface == "NVMe":
        # Nothing structured to extract; the record is enough to render the
        # NVMe degraded output in evaluate_nvme().
        pass

    return rec


def _format_capacity(bytes_val):
    """Format byte count as a human-readable capacity string."""
    for unit, factor in (("TB", 1e12), ("GB", 1e9), ("MB", 1e6)):
        if bytes_val >= factor:
            return f"{bytes_val / factor:.1f} {unit}"
    return f"{bytes_val} B"


def parse_nvme_file(path):
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            raw = f.read()
    except OSError:
        return []

    if not raw.strip():
        return []

    rec = new_disk_record(source_file=path, source_line=1, interface="NVMe")
    rec["model"] = parse_kv(raw, "Model Number") or parse_kv(raw, "Device Model")
    rec["serial"] = parse_kv(raw, "Serial Number")
    m = re.search(r"(/dev/nvme\S+)", raw)
    if m:
        rec["device"] = m.group(1).rstrip(":")
    return [rec]


# ---------------------------------------------------------------------------
# Rule evaluation
# ---------------------------------------------------------------------------
def evidence_str(path, line):
    if line is None:
        return f"[{path} : N/A]"
    return f"[{path} : {line}]"


# ---------------------------------------------------------------------------
# Volume map (device → vol_id)
# ---------------------------------------------------------------------------
def load_volume_map(log_root, explicit_path=None):
    """Search for diskmap.txt / mount-like outputs and return device → vol_id."""
    mapping = {}

    candidates = []
    if explicit_path and os.path.isfile(explicit_path):
        candidates.append(explicit_path)
    candidates.extend(find_files(log_root, r"^diskmap.*\.txt$"))
    candidates.extend(find_files(log_root, r"^mount.*\.txt$"))
    candidates.extend(find_files(log_root, r"^lsblk.*\.txt$"))

    # Line patterns supported:
    #   "/dev/sdX  vol13"
    #   "vol13     /dev/sdX"
    #   "/dev/sdX  ...  /mnt/vol13"
    line_re = re.compile(
        r"(?:(?P<volA>vol\w+)\s+(?P<devA>/dev/\S+))"
        r"|(?:(?P<devB>/dev/\S+)\s+(?P<volB>vol\w+))"
        r"|(?:(?P<devC>/dev/\S+).*?/mnt/(?P<volC>vol\w+))"
    )
    for path in candidates:
        try:
            with open(path, "r", encoding="utf-8", errors="ignore") as f:
                for line in f:
                    m = line_re.search(line)
                    if not m:
                        continue
                    dev = m.group("devA") or m.group("devB") or m.group("devC")
                    vol = m.group("volA") or m.group("volB") or m.group("volC")
                    if dev and vol:
                        mapping[dev.rstrip(":")] = vol
        except OSError:
            continue
    return mapping


def attach_volume_map(disks, vol_map):
    for rec in disks:
        if rec.get("device") and rec["device"] in vol_map:
            rec["vol_id"] = vol_map[rec["device"]]


# ---------------------------------------------------------------------------
# Standardized output derivations (SKILL.md §3.5 / §3.7)
# ---------------------------------------------------------------------------
def compute_replacement(rec):
    """True iff survival == 0 or survival < 30%; None for NVMe/strict-N/A."""
    if rec["interface"] == "NVMe":
        return None
    s = rec.get("survival_prob")
    if s is None:
        return None
    return s < 0.30


def compute_repairable(rec):
    """Based on the RULE_REPAIRABLE_MAP; multiple hits → strictest (False wins)."""
    if rec["interface"] == "NVMe":
        return None
    hits = [r for r in rec["rule_results"] if r["hit"] is True]
    if not hits:
        # No rule hit ⇒ repairable iff replacement is False
        return compute_replacement(rec) is False
    verdict = True
    for r in hits:
        repairable = RULE_REPAIRABLE_MAP.get(r["rule_id"], False)
        if not repairable:
            verdict = False
            break
    return verdict


def compute_failure_rules_hit(rec):
    """List of '<rule_id>: <short desc> (<actual> vs <threshold>)' strings."""
    out = []
    for r in rec["rule_results"]:
        if r["hit"] is not True:
            continue
        desc_en, _desc_zh = RULE_SHORT_DESC.get(r["rule_id"],
                                                 (r["description"], r["description"]))
        out.append(f"{r['rule_id']}: {desc_en} ({r['actual']} vs {r['threshold']})")
    return out


def compute_analysis_reasons(rec):
    """Natural-language reasoning list per SKILL.md §3.7."""
    reasons = []

    # NVMe degraded path
    if rec["interface"] == "NVMe":
        reasons.append(
            "NVMe 介质未覆盖 disk_health_rules.md 规则集；请在受影响主机执行 "
            "`nvme smart-log <dev>` / `nvme error-log <dev>` / "
            "`nvme self-test-log <dev>`，关注 Critical Warning、Media and "
            "Data Integrity Errors、Percentage Used、Available Spare、"
            "Available Spare Threshold 等指标。"
        )
        if rec.get("vol_id") is None:
            reasons.append(
                "未在日志中找到 {} 到卷的映射关系，建议补充 diskmap.txt 或挂载点信息。"
                .format(rec.get("device") or "设备")
            )
        return reasons

    # vol_id missing
    if rec.get("vol_id") is None:
        reasons.append(
            "未在日志中找到 {} 到卷的映射关系，建议补充 diskmap.txt 或挂载点信息。"
            .format(rec.get("device") or "设备")
        )

    # Hard-fault rules hit → translated short reasons
    hits = [r for r in rec["rule_results"] if r["hit"] is True]
    for r in hits:
        _en, zh = RULE_SHORT_DESC.get(r["rule_id"], (r["description"], r["description"]))
        reasons.append(f"{zh}：实测 {r['actual']}，触发阈值 {r['threshold']}（{r['rule_id']}）")

    # Degradation reasons (deviation > 0.5 even if no hard rule hit)
    if not hits:
        for name, d in rec.get("deviations", {}).items():
            if d["deviation"] > 0.5:
                reasons.append(
                    f"{name} 偏离度 {d['deviation']*100:.1f}%（实测 {d['actual']} / "
                    f"阈值 {d['threshold']} / 健康值 {d['healthy']}），需重点关注。"
                )

    # Data missing notes
    na_rules = [r["rule_id"] for r in rec["rule_results"] if r["hit"] is None
                and not r["rule_id"].startswith("NVMe")]
    if na_rules:
        reasons.append(
            "以下规则因数据缺失无法判定：{}；建议补全 SMART 数据后复检。"
            .format(", ".join(na_rules))
        )

    # Healthy default
    if not reasons:
        reasons.append("未命中任何故障规则")
    elif hits and rec.get("survival_prob") == 0.0 and not any(
            "未命中" in s for s in reasons):
        # Already covered; nothing extra
        pass

    return reasons


def evaluate(rec, messages_dir=None):
    """Populate rec['rule_results'], rec['survival_prob'], rec['action_level']."""
    iface = rec["interface"]
    if iface == "NVMe":
        evaluate_nvme(rec)
        return
    if iface == "SAS":
        evaluate_sas(rec, messages_dir)
    elif iface == "SATA":
        evaluate_sata(rec)
    else:
        rec["action_level"] = "Cannot evaluate (interface unknown)"
        rec["notes"].append(
            "Interface could not be detected from smartctl output."
        )
        return

    # Survival probability (only when no rule was hit)
    if any(r["hit"] is True for r in rec["rule_results"]):
        rec["survival_prob"] = 0.0
        rec["action_level"] = action_for(0.0)
        return

    compute_survival(rec)


# ---- SAS -----------------------------------------------------------------
def evaluate_sas(rec, messages_dir):
    src = rec["source_file"]
    f = rec["fields"]

    # SAS-R1: defects > 1000
    defect = f.get("defect_list")
    if defect is not None:
        actual = defect["value"]
        rec["rule_results"].append(new_rule_result(
            "SAS-R1",
            "Elements in grown defect list",
            f"> {SAS_THRESHOLDS['defect_list_max']}",
            actual,
            actual > SAS_THRESHOLDS["defect_list_max"],
            evidence_str(src, defect["line"]),
        ))
    else:
        rec["rule_results"].append(new_rule_result(
            "SAS-R1", "Elements in grown defect list", "> 1000",
            "N/A", None, evidence_str(src, None),
            note="Field not found in source file.",
        ))

    # SAS-R2: uncorrected errors
    w = f.get("uncorrected_write")
    r = f.get("uncorrected_read")
    v = f.get("uncorrected_verify")
    if w and r and v:
        hit = (w["value"] > SAS_THRESHOLDS["uncorrected_write_max"]
               or r["value"] > SAS_THRESHOLDS["uncorrected_read_max"]
               or v["value"] > SAS_THRESHOLDS["uncorrected_verify_max"])
        actual = f"write={w['value']}, read={r['value']}, verify={v['value']}"
        rec["rule_results"].append(new_rule_result(
            "SAS-R2",
            "Total uncorrected errors",
            "write>50 OR read>1000 OR verify>1000",
            actual,
            hit,
            evidence_str(src, w["line"]),
        ))
    else:
        rec["rule_results"].append(new_rule_result(
            "SAS-R2", "Total uncorrected errors",
            "write>50 OR read>1000 OR verify>1000",
            "N/A", None, evidence_str(src, None),
            note="One or more of write/read/verify rows not found.",
        ))

    # SAS-R3: SMART Health Status != OK
    hs = f.get("health_status")
    if hs is not None:
        actual = hs["value"]
        rec["rule_results"].append(new_rule_result(
            "SAS-R3",
            "SMART Health Status",
            "!= OK",
            actual,
            actual.upper() != "OK",
            evidence_str(src, hs["line"]),
        ))
    else:
        rec["rule_results"].append(new_rule_result(
            "SAS-R3", "SMART Health Status", "!= OK",
            "N/A", None, evidence_str(src, None),
            note="Health status line not found.",
        ))

    # SAS-R4: asc=0x5d (predictive failure) — search messages/dmesg if given
    asc_hit = False
    asc_evidence = None
    if messages_dir and os.path.isdir(messages_dir):
        for path in find_files(messages_dir, r"(messages.*|dmesg.*|syslog.*)"):
            try:
                with open(path, "r", encoding="utf-8", errors="ignore") as fh:
                    for i, line in enumerate(fh, start=1):
                        if "asc=0x5d" in line.lower():
                            asc_hit = True
                            asc_evidence = evidence_str(path, i)
                            break
            except OSError:
                continue
            if asc_hit:
                break
    rec["rule_results"].append(new_rule_result(
        "SAS-R4",
        "asc=0x5d predictive failure",
        "appears",
        "found" if asc_hit else "not found",
        asc_hit if messages_dir else None,
        asc_evidence or evidence_str(messages_dir or "(messages dir not provided)",
                                     None),
        note=None if messages_dir else
             "messages_dir not supplied; cannot search for asc=0x5d.",
    ))

    # Stash numeric fields for survival probability
    if defect is not None:
        rec["fields"]["_numeric_defect"] = defect["value"]
    if w is not None:
        rec["fields"]["_numeric_uncorr_write"] = w["value"]
    if r is not None:
        rec["fields"]["_numeric_uncorr_read"] = r["value"]
    if v is not None:
        rec["fields"]["_numeric_uncorr_verify"] = v["value"]


# ---- SATA ----------------------------------------------------------------
def evaluate_sata(rec):
    src = rec["source_file"]
    f = rec["fields"]
    attrs = f.get("smart_attrs", {})

    # SATA-R1: SMART Error Log != "No Errors Logged"
    el = f.get("error_log")
    el_line = f.get("error_log_line")
    if el is not None:
        rec["rule_results"].append(new_rule_result(
            "SATA-R1",
            "SMART Error Log",
            '!= "No Errors Logged"',
            el,
            el != "No Errors Logged",
            evidence_str(src, el_line),
        ))
    else:
        rec["rule_results"].append(new_rule_result(
            "SATA-R1", "SMART Error Log", '!= "No Errors Logged"',
            "N/A", None, evidence_str(src, None),
            note="Error log section not found.",
        ))

    # SATA-R2: overall-health != PASSED
    health = f.get("health")
    h_line = f.get("health_line")
    if health is not None:
        rec["rule_results"].append(new_rule_result(
            "SATA-R2",
            "SMART overall-health self-assessment",
            "!= PASSED",
            health,
            health.upper() != "PASSED",
            evidence_str(src, h_line),
        ))
    else:
        rec["rule_results"].append(new_rule_result(
            "SATA-R2", "SMART overall-health self-assessment", "!= PASSED",
            "N/A", None, evidence_str(src, None),
            note="Health line not found.",
        ))

    # Numeric RAW-based rules (R3 / R4 / R5 / R10)
    raw_rules = [
        ("SATA-R3", 5,   "Reallocated_Sector_Ct (RAW)",
         SATA_THRESHOLDS["reallocated_max"]),
        ("SATA-R4", 197, "Current_Pending_Sector (RAW)",
         SATA_THRESHOLDS["pending_max"]),
        ("SATA-R5", 198, "Offline_Uncorrectable (RAW)",
         SATA_THRESHOLDS["offline_uncorrectable_max"]),
        ("SATA-R10", 9,  "Power_On_Hours",
         SATA_THRESHOLDS["power_on_hours_max"]),
    ]
    for rule_id, attr_id, desc, thresh in raw_rules:
        a = attrs.get(attr_id)
        if a and a["raw"] is not None:
            actual = a["raw"]
            rec["rule_results"].append(new_rule_result(
                rule_id, desc, f">= {thresh}", actual,
                actual >= thresh, evidence_str(src, a["line"]),
            ))
        else:
            rec["rule_results"].append(new_rule_result(
                rule_id, desc, f">= {thresh}", "N/A", None,
                evidence_str(src, None),
                note=f"SMART attribute ID {attr_id} not found.",
            ))

    # SATA-R6: UDMA_CRC_Error_Count != 0 and growing
    crc = attrs.get(199)
    if crc and crc["raw"] is not None:
        actual = crc["raw"]
        # Single snapshot — cannot detect growth. Flag != 0 as conditional hit.
        if actual != 0:
            note = ("RAW != 0; growth trend cannot be confirmed from a single "
                    "snapshot — recommend re-sampling on the live host.")
            rec["rule_results"].append(new_rule_result(
                "SATA-R6",
                "UDMA_CRC_Error_Count (single snapshot)",
                "!= 0 and growing",
                actual,
                None,
                evidence_str(src, crc["line"]),
                note=note,
            ))
        else:
            rec["rule_results"].append(new_rule_result(
                "SATA-R6", "UDMA_CRC_Error_Count",
                "!= 0 and growing", actual, False,
                evidence_str(src, crc["line"]),
            ))
    else:
        rec["rule_results"].append(new_rule_result(
            "SATA-R6", "UDMA_CRC_Error_Count",
            "!= 0 and growing", "N/A", None, evidence_str(src, None),
            note="SMART attribute ID 199 not found.",
        ))

    # SATA-R7 / R8: WORST <= Thresh * 1.05
    rate_rules = [
        ("SATA-R7", 1, "Raw_Read_Error_Rate WORST <= Thresh*1.05"),
        ("SATA-R8", 7, "Seek_Error_Rate WORST <= Thresh*1.05"),
    ]
    for rule_id, attr_id, desc in rate_rules:
        a = attrs.get(attr_id)
        if a:
            limit = a["thresh"] * SATA_THRESHOLDS["rate_factor"]
            hit = a["worst"] <= limit
            rec["rule_results"].append(new_rule_result(
                rule_id, desc,
                f"worst<= thresh*{SATA_THRESHOLDS['rate_factor']} (={limit:.2f})",
                a["worst"], hit, evidence_str(src, a["line"]),
            ))
        else:
            rec["rule_results"].append(new_rule_result(
                rule_id, desc, "worst<= thresh*1.05",
                "N/A", None, evidence_str(src, None),
                note=f"SMART attribute ID {attr_id} not found.",
            ))

    # SATA-R9: Spin_Up_Time VALUE <= 30%*(Default-Thresh)+Thresh
    a = attrs.get(3)
    if a:
        default = (WD_SPIN_UP_DEFAULT if rec.get("vendor") == "WD"
                   else OTHER_SPIN_UP_DEFAULT)
        limit = SATA_THRESHOLDS["spin_up_factor"] * (default - a["thresh"]) \
                + a["thresh"]
        hit = a["value"] <= limit
        rec["rule_results"].append(new_rule_result(
            "SATA-R9",
            f"Spin_Up_Time VALUE (Default={default}, Thresh={a['thresh']})",
            f"value <= {limit:.2f}",
            a["value"], hit, evidence_str(src, a["line"]),
        ))
    else:
        rec["rule_results"].append(new_rule_result(
            "SATA-R9", "Spin_Up_Time VALUE",
            "value <= 30%*(Default-Thresh)+Thresh",
            "N/A", None, evidence_str(src, None),
            note="SMART attribute ID 3 not found.",
        ))


# ---- NVMe ----------------------------------------------------------------
def evaluate_nvme(rec):
    rec["notes"].append("rule.md does not cover NVMe; assessment skipped.")
    rec["action_level"] = "Cannot evaluate (NVMe — rule set not covered)"
    rec["survival_prob"] = None
    rec["rule_results"].append({
        "rule_id": "NVMe-N/A",
        "description": "NVMe medium not covered by rule.md",
        "threshold": "—",
        "actual": "—",
        "hit": None,
        "evidence": evidence_str(rec["source_file"], rec["source_line"]),
        "note": ("Run the following on the affected host to obtain a live "
                 "self check: `nvme smart-log <dev>`, `nvme error-log <dev>`, "
                 "`nvme self-test-log <dev>`. Watch Critical Warning, Media "
                 "and Data Integrity Errors, Percentage Used, Available "
                 "Spare and Available Spare Threshold."),
    })


# ---- Survival probability ------------------------------------------------
def compute_survival(rec):
    iface = rec["interface"]
    attrs = rec["fields"].get("smart_attrs", {})
    deviations = OrderedDict()

    def add_forward(name, actual, healthy, thresh):
        if actual is None or thresh == healthy:
            return
        dev = (actual - healthy) / (thresh - healthy)
        deviations[name] = {
            "actual": actual, "healthy": healthy, "threshold": thresh,
            "deviation": max(0.0, min(1.0, dev)),
        }

    def add_reverse(name, actual, healthy, thresh):
        if actual is None or healthy == thresh:
            return
        dev = (healthy - actual) / (healthy - thresh)
        deviations[name] = {
            "actual": actual, "healthy": healthy, "threshold": thresh,
            "deviation": max(0.0, min(1.0, dev)),
        }

    if iface == "SATA":
        for attr_id, name, thresh in [
            (5,   "Reallocated_Sector_Ct",    SATA_THRESHOLDS["reallocated_max"]),
            (197, "Current_Pending_Sector",   SATA_THRESHOLDS["pending_max"]),
            (198, "Offline_Uncorrectable",    SATA_THRESHOLDS["offline_uncorrectable_max"]),
            (9,   "Power_On_Hours",           SATA_THRESHOLDS["power_on_hours_max"]),
        ]:
            a = attrs.get(attr_id)
            if a and a["raw"] is not None:
                add_forward(name, a["raw"], 0, thresh)

        # Raw_Read_Error_Rate (id 1) and Seek_Error_Rate (id 7) — reverse, WORST
        for attr_id, name in [(1, "Raw_Read_Error_Rate"), (7, "Seek_Error_Rate")]:
            a = attrs.get(attr_id)
            if a:
                healthy = 100   # SMART normalized scale top end
                thresh = a["thresh"] * SATA_THRESHOLDS["rate_factor"]
                add_reverse(name, a["worst"], healthy, thresh)

        # Spin_Up_Time (id 3) — reverse, VALUE
        a = attrs.get(3)
        if a:
            default = (WD_SPIN_UP_DEFAULT if rec.get("vendor") == "WD"
                       else OTHER_SPIN_UP_DEFAULT)
            thresh = SATA_THRESHOLDS["spin_up_factor"] * (default - a["thresh"]) \
                     + a["thresh"]
            add_reverse("Spin_Up_Time", a["value"], default, thresh)

    elif iface == "SAS":
        f = rec["fields"]
        if "_numeric_defect" in f:
            add_forward("Elements_in_grown_defect_list",
                        f["_numeric_defect"], 0,
                        SAS_THRESHOLDS["defect_list_max"])
        if "_numeric_uncorr_write" in f:
            add_forward("Uncorrected_Write", f["_numeric_uncorr_write"], 0,
                        SAS_THRESHOLDS["uncorrected_write_max"])
        if "_numeric_uncorr_read" in f:
            add_forward("Uncorrected_Read", f["_numeric_uncorr_read"], 0,
                        SAS_THRESHOLDS["uncorrected_read_max"])
        if "_numeric_uncorr_verify" in f:
            add_forward("Uncorrected_Verify", f["_numeric_uncorr_verify"], 0,
                        SAS_THRESHOLDS["uncorrected_verify_max"])

    rec["deviations"] = deviations
    if not deviations:
        rec["survival_prob"] = None
        rec["action_level"] = ("Survival probability incomplete "
                               "(no numeric indicators recovered)")
        return

    max_dev = max(d["deviation"] for d in deviations.values())
    survival = max(0.0, min(1.0, 1.0 - max_dev))
    rec["survival_prob"] = survival
    rec["action_level"] = action_for(survival)


# ---------------------------------------------------------------------------
# Standardized output object assembly (SKILL.md §3.7)
# ---------------------------------------------------------------------------
def build_standard_object(rec):
    """Translate an internal disk record into the §3.7 13-field volume entry."""
    return OrderedDict([
        ("vol_id", rec.get("vol_id")),
        ("device", rec.get("device")),
        ("model", rec.get("model")),
        ("serial", rec.get("serial")),
        ("interface", rec.get("interface")),
        ("capacity", rec.get("capacity")),
        ("power_on_hours", rec.get("power_on_hours")),
        ("replacement", compute_replacement(rec)),
        ("repairable", compute_repairable(rec)),
        ("half_year_survival_probability",
            None if rec["interface"] == "NVMe" else rec.get("survival_prob")),
        ("failure_rules_hit", compute_failure_rules_hit(rec)),
        ("analysis_reasons", compute_analysis_reasons(rec)),
    ])


def build_report(disks, ip=None, analysis_time=None):
    """Top-level report envelope { ip, analysis_time, volumes[] }."""
    from datetime import date
    return OrderedDict([
        ("ip", ip or "unknown"),
        ("analysis_time", analysis_time or date.today().isoformat()),
        ("volumes", [build_standard_object(d) for d in disks]),
    ])


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------
def render_card(report, disks):
    """Human-readable card view, one block per volume."""
    out = []
    out.append("=" * 70)
    out.append("Step 3 — Health Rule Compliance")
    out.append("=" * 70)
    out.append(f"  IP            : {report['ip']}")
    out.append(f"  Analysis Time : {report['analysis_time']}")
    if not report["volumes"]:
        out.append("")
        out.append("No disks discovered. Make sure disk_smart.txt or similar "
                   "files are present under the given log directory.")
        out.append("=" * 70)
        return "\n".join(out)

    for vol, rec in zip(report["volumes"], disks):
        out.append("")
        out.append("-" * 70)
        vol_display = vol["vol_id"] if vol["vol_id"] is not None else "(no vol_id)"
        dev_display = vol["device"] or "(unknown device)"
        out.append(f"Volume: {vol_display}  |  Device: {dev_display}")
        out.append("-" * 70)
        out.append(f"  Model        : {vol['model'] or '?'}")
        out.append(f"  Serial       : {vol['serial'] or '?'}")
        out.append(f"  Interface    : {vol['interface']}"
                   f"          Capacity: {vol['capacity'] or '?'}")
        out.append(f"  Power-On     : "
                   f"{vol['power_on_hours'] if vol['power_on_hours'] is not None else '?'} h")
        if rec.get("slot"):
            out.append(f"  Slot         : {rec['slot']}")

        out.append("")
        if vol["failure_rules_hit"]:
            out.append("  Failure Rules Hit:")
            for r in vol["failure_rules_hit"]:
                out.append(f"    ✕ {r}")
        else:
            out.append("  Failure Rules Hit:  (none)")

        out.append("")
        hys = vol["half_year_survival_probability"]
        hys_str = f"{hys*100:.1f}%" if hys is not None else "null (NVMe — not covered)"
        out.append(f"  Half-Year Survival:  {hys_str}")
        out.append(f"  Replacement Needed:  {_bool_display(vol['replacement'])}")
        out.append(f"  Repairable:          {_bool_display(vol['repairable'])}")

        out.append("")
        out.append("  Analysis Reasons:")
        for r in vol["analysis_reasons"]:
            out.append(f"    • {r}")

        # Deviation details (numeric indicator breakdown)
        if rec.get("deviations"):
            out.append("")
            out.append("  Deviation Details:")
            for name, d in rec["deviations"].items():
                out.append(f"    {name:<32} actual={d['actual']} "
                           f"healthy={d['healthy']} threshold={d['threshold']} "
                           f"dev={d['deviation']:.3f}")

        out.append("")
        out.append(f"  Evidence: [{rec['source_file']} : {rec['source_line']}]")

    out.append("")
    out.append("=" * 70)
    return "\n".join(out)


def _bool_display(value):
    if value is True:
        return "Yes"
    if value is False:
        return "No"
    return "null"


def render_strict_json(report):
    """User-specified schema (13 fields per volume + 2 report-level)."""
    return json.dumps(report, indent=2, ensure_ascii=False, default=str)


def render_extended_json(report, disks):
    """Strict schema + evidence/deviations sidecar for upstream tooling."""
    enriched = OrderedDict(report)
    enriched["volumes"] = []
    for vol, rec in zip(report["volumes"], disks):
        v = OrderedDict(vol)
        v["_evidence"] = f"[{rec['source_file']} : {rec['source_line']}]"
        v["_vendor"] = rec.get("vendor")
        v["_deviations"] = rec.get("deviations") or {}
        v["_rule_results"] = rec.get("rule_results") or []
        enriched["volumes"].append(v)
    return json.dumps(enriched, indent=2, ensure_ascii=False, default=str)


def render_md_report(report, disks):
    """Markdown report mirroring the card view (for embedding in Step 5 §5)."""
    out = []
    out.append("## Step 3 — Health Rule Compliance")
    out.append("")
    out.append(f"- **IP**: `{report['ip']}`")
    out.append(f"- **Analysis Time**: `{report['analysis_time']}`")
    out.append(f"- **Volumes Assessed**: {len(report['volumes'])}")
    if not report["volumes"]:
        out.append("\n_No disks discovered._")
        return "\n".join(out)

    for vol, rec in zip(report["volumes"], disks):
        vol_display = vol["vol_id"] if vol["vol_id"] is not None else "(no vol_id)"
        dev_display = vol["device"] or "(unknown)"
        out.append(f"\n### Volume: {vol_display} — {dev_display}")
        out.append("")
        out.append(f"- **Interface**: {vol['interface']}")
        out.append(f"- **Model**: {vol['model'] or '?'}")
        out.append(f"- **Serial**: {vol['serial'] or '?'}")
        out.append(f"- **Capacity**: {vol['capacity'] or '?'}")
        ph = vol["power_on_hours"]
        out.append(f"- **Power-On**: {ph if ph is not None else '?'} h")
        if rec.get("slot"):
            out.append(f"- **Slot**: {rec['slot']}")
        hys = vol["half_year_survival_probability"]
        hys_str = f"{hys*100:.1f}%" if hys is not None else "null"
        out.append(f"- **Half-Year Survival**: {hys_str}")
        out.append(f"- **Replacement**: {_bool_display(vol['replacement'])}")
        out.append(f"- **Repairable**: {_bool_display(vol['repairable'])}")
        out.append(f"- **Evidence**: `[{rec['source_file']} : {rec['source_line']}]`")

        if vol["failure_rules_hit"]:
            out.append("")
            out.append("**Failure Rules Hit:**")
            for r in vol["failure_rules_hit"]:
                out.append(f"- ✕ {r}")
        else:
            out.append("\n**Failure Rules Hit:** _(none)_")

        out.append("")
        out.append("**Analysis Reasons:**")
        for r in vol["analysis_reasons"]:
            out.append(f"- {r}")

        if rec.get("deviations"):
            out.append("")
            out.append("**Deviation Details:**")
            out.append("")
            out.append("| Indicator | Actual | Healthy | Threshold | Deviation |")
            out.append("| --- | --- | --- | --- | --- |")
            for name, d in rec["deviations"].items():
                out.append(f"| {name} | {d['actual']} | {d['healthy']} | "
                           f"{d['threshold']} | {d['deviation']:.3f} |")
    return "\n".join(out)


def render_table(disks, include_passed=False):
    out = []
    out.append("=" * 70)
    out.append("Step 3 — Health Rule Compliance")
    out.append("=" * 70)
    if not disks:
        out.append("No disks discovered. Make sure disk_smart.txt or similar "
                   "files are present under the given log directory.")
        return "\n".join(out)

    for idx, rec in enumerate(disks, 1):
        out.append("")
        out.append(f"[Disk {idx}] {rec.get('device') or '(unknown device)'} "
                   f"| Slot={rec.get('slot') or '?'} "
                   f"| Interface={rec['interface']} "
                   f"| Model={rec.get('model') or '?'} "
                   f"| Serial={rec.get('serial') or '?'} "
                   f"| Vendor={rec.get('vendor') or '?'}")
        out.append(f"  Source: [{rec['source_file']} : {rec['source_line']}]")

        # Rule table
        out.append("  Rule Hits:")
        out.append("  {:<10} {:<48} {:<24} {:<24} {:<6} {}".format(
            "Rule", "Description", "Threshold", "Actual", "Hit", "Evidence"
        ))
        for r in rec["rule_results"]:
            if r["hit"] is False and not include_passed:
                continue
            hit_txt = ("YES" if r["hit"] is True else
                       "no"  if r["hit"] is False else "N/A")
            out.append("  {:<10} {:<48} {:<24} {:<24} {:<6} {}".format(
                str(r["rule_id"]),
                str(r["description"])[:48],
                str(r["threshold"])[:24],
                str(r["actual"])[:24],
                hit_txt,
                r["evidence"],
            ))
            if r.get("note"):
                out.append(f"             note: {r['note']}")

        # Deviations / survival
        if rec["deviations"]:
            out.append("  Deviations:")
            for name, d in rec["deviations"].items():
                out.append("    {:<32} actual={} healthy={} threshold={} dev={:.3f}"
                           .format(name, d["actual"], d["healthy"],
                                   d["threshold"], d["deviation"]))
        if rec["survival_prob"] is not None:
            out.append(f"  Survival Probability: {rec['survival_prob']*100:.1f}%")
        out.append(f"  Action: {rec['action_level']}")

        for n in rec["notes"]:
            out.append(f"  Note: {n}")

    out.append("")
    out.append("=" * 70)
    return "\n".join(out)


def render_md(disks):
    out = ["## Step 3 — Health Rule Compliance"]
    if not disks:
        out.append("\n_No disks discovered._")
        return "\n".join(out)

    for idx, rec in enumerate(disks, 1):
        out.append(f"\n### Disk {idx} — {rec.get('device') or '(unknown)'} "
                   f"(Slot {rec.get('slot') or '?'})")
        out.append("")
        out.append(f"- **Interface**: {rec['interface']}")
        out.append(f"- **Model**: {rec.get('model') or '?'}")
        out.append(f"- **Serial**: {rec.get('serial') or '?'}")
        out.append(f"- **Vendor**: {rec.get('vendor') or '?'}")
        out.append(f"- **Source**: `[{rec['source_file']} : {rec['source_line']}]`")

        out.append("")
        out.append("| Rule | Description | Threshold | Actual | Hit | Evidence |")
        out.append("| --- | --- | --- | --- | --- | --- |")
        for r in rec["rule_results"]:
            hit_txt = ("✅" if r["hit"] is True else
                       "❌" if r["hit"] is False else "N/A")
            out.append("| {} | {} | {} | {} | {} | `{}` |".format(
                r["rule_id"], r["description"], r["threshold"],
                r["actual"], hit_txt, r["evidence"]))
            if r.get("note"):
                out.append(f"|  | _note: {r['note']}_ |  |  |  |  |")

        if rec["deviations"]:
            out.append("")
            out.append("| Indicator | Actual | Healthy | Threshold | Deviation |")
            out.append("| --- | --- | --- | --- | --- |")
            for name, d in rec["deviations"].items():
                out.append("| {} | {} | {} | {} | {:.3f} |".format(
                    name, d["actual"], d["healthy"], d["threshold"],
                    d["deviation"]))

        if rec["survival_prob"] is not None:
            out.append("")
            out.append(f"**Survival Probability**: "
                       f"{rec['survival_prob']*100:.1f}%")
        out.append(f"**Action**: {rec['action_level']}")
        for n in rec["notes"]:
            out.append(f"\n> Note: {n}")

    return "\n".join(out)


def render_json(disks):
    return json.dumps(disks, indent=2, ensure_ascii=False, default=str)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def _infer_ip_from_path(path):
    """Best-effort extraction of an IPv4 segment from the log_dir path."""
    m = re.search(r"\b((?:\d{1,3}\.){3}\d{1,3})\b", path)
    return m.group(1) if m else None


def main():
    parser = argparse.ArgumentParser(
        description="Disk health rule evaluation (Step 3 of offline disk "
                    "fault diagnosis). Produces a standardized 13-field "
                    "diagnostic object per volume (SKILL.md §3.7).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Usage Examples:
  python3 %(prog)s ./logs/                         # card view (default)
  python3 %(prog)s ./logs/ --format json           # strict JSON schema
  python3 %(prog)s ./logs/ --format json-extended  # JSON + evidence sidecar
  python3 %(prog)s ./logs/ --format md             # Markdown report
  python3 %(prog)s ./logs/ --ip 10.78.26.27 --vol-map ./diskmap.txt
  python3 %(prog)s ./logs/ --slot 4 --slot 5 --include-passed
        """,
    )
    parser.add_argument("log_dir",
                        help="Root directory of the log bundle. The script "
                             "recursively searches for disk_smart.txt, "
                             "sasraidlog.txt, nvme*.txt etc.")
    parser.add_argument("--ip", metavar="ADDR", default=None,
                        help="Server IP for the report header. If omitted, "
                             "inferred from the log_dir path.")
    parser.add_argument("--vol-map", metavar="PATH", default=None,
                        help="Explicit device→vol_id mapping file (diskmap "
                             "style: '/dev/sdX  volNN' lines).")
    parser.add_argument("--rule", metavar="PATH", default=None,
                        help="Path to disk_health_rules.md (informational; "
                             "thresholds are hard-coded as constants).")
    parser.add_argument("--format",
                        choices=("card", "json", "json-extended", "md", "table"),
                        default="card",
                        help="Output format (default: card). 'json' follows "
                             "the strict §3.7 schema; 'json-extended' adds "
                             "evidence/deviations sidecar fields.")
    parser.add_argument("--slot", action="append", default=[],
                        help="Only evaluate the given slot id (repeatable).")
    parser.add_argument("--device", action="append", default=[],
                        help="Only evaluate the given device name (repeatable).")
    parser.add_argument("--include-passed", action="store_true",
                        help="Show non-hit rule rows in the output as well "
                             "(table mode only).")
    parser.add_argument("--strict", action="store_true",
                        help="Treat any N/A field as 'Cannot evaluate'.")

    args = parser.parse_args()

    if not os.path.isdir(args.log_dir):
        print(f"Error: {args.log_dir} is not a directory.", file=sys.stderr)
        sys.exit(1)

    log_root = os.path.abspath(args.log_dir)

    # Locate messages dir if present (sibling or child)
    messages_dir = None
    for cand in (os.path.join(log_root, "messages"),
                 os.path.join(os.path.dirname(log_root), "messages")):
        if os.path.isdir(cand):
            messages_dir = cand
            break

    disks = discover_disks(log_root)

    # Volume map
    vol_map = load_volume_map(log_root, explicit_path=args.vol_map)
    attach_volume_map(disks, vol_map)

    # Filter
    if args.slot:
        disks = [d for d in disks if str(d.get("slot")) in args.slot]
    if args.device:
        keep = []
        for d in disks:
            dev = (d.get("device") or "").rstrip("/")
            if any(name in dev for name in args.device):
                keep.append(d)
        disks = keep

    # Evaluate
    for rec in disks:
        evaluate(rec, messages_dir=messages_dir)
        if args.strict:
            if any(r["hit"] is None for r in rec["rule_results"]):
                rec["action_level"] = "Cannot evaluate (strict mode — N/A fields)"
                rec["survival_prob"] = None

    # Resolve IP
    ip = args.ip or _infer_ip_from_path(log_root)

    # Build standardized report envelope
    report = build_report(disks, ip=ip)

    # Render
    fmt = args.format
    if fmt == "json":
        print(render_strict_json(report))
    elif fmt == "json-extended":
        print(render_extended_json(report, disks))
    elif fmt == "md":
        print(render_md_report(report, disks))
    elif fmt == "table":
        # Legacy view kept for back-compat; show report header + per-disk table
        print(f"IP={report['ip']}  AnalysisTime={report['analysis_time']}  "
              f"Volumes={len(report['volumes'])}")
        print(render_table(disks, include_passed=args.include_passed))
    else:
        # default: card
        print(render_card(report, disks))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
triage.py - static + VirusTotal-hash file triage.

Part of the C:\\Sync security ecosystem (Backlog task T081).

What it does
------------
Given a file path it produces a JSON risk summary by combining:
  * file-type identification           (oletools.ftguess)
  * SHA-256 hash                       (hashlib)
  * EICAR test-signature scan          (literal string match - works offline)
  * Office macro analysis              (oletools: OleID + olevba)  for OLE/OpenXML
  * PDF structural keyword scan        (pdfid)                     for PDF
  * VirusTotal HASH-ONLY lookup        (vt-py)   - opt-in, never uploads the file

Safety
------
  * The file content is NEVER uploaded anywhere. Only the SHA-256 hash is sent
    to VirusTotal (and only when --vt is given and an API key is present).
  * Evaluate genuinely suspicious files on a separate clean VM, not this host.
  * VT free tier: 4 requests/min, 500/day - this tool throttles to <= 4/min.

Usage
-----
  python triage.py <file>                 # static analysis, JSON to stdout
  python triage.py <file> --vt            # also do a VirusTotal hash lookup
  python triage.py <file> --pretty        # human-readable instead of raw JSON
  python triage.py --watch <folder>       # watch a drop-folder, triage new files
  python triage.py --watch <folder> --vt --log <file>

Exit code
---------
  0  verdict == clean / low
  2  verdict == suspicious / medium
  3  verdict == malicious / high / critical
  1  triage error (could not analyse)

VirusTotal API key: set env var VIRUSTOTAL_API_KEY (or VT_API_KEY).
"""

import argparse
import hashlib
import json
import os
import sys
import time
import traceback
from datetime import datetime, timezone

# ---- EICAR anti-virus test signature (safe, not a real virus) ---------------
# https://www.eicar.org/download-anti-malware-testfile/
EICAR = (
    "X5O!P%@AP[4\\PZX54(P^)7CC)7}$EICAR"
    "-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*"
)
EICAR_SHA256 = "275a021bbfb6489e54d471899f7db9d1663fc695ec2fe2a2c4538aabf651fd0f"

VERDICT_EXIT = {
    "clean": 0, "low": 0,
    "medium": 2, "suspicious": 2,
    "high": 3, "critical": 3, "malicious": 3,
}

# PDF structural keywords that indicate active/embedded content.
PDF_RISKY_KEYWORDS = (
    "/JS", "/JavaScript", "/OpenAction", "/AA",
    "/Launch", "/EmbeddedFile", "/RichMedia", "/AcroForm", "/JBIG2Decode",
)


def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# -----------------------------------------------------------------------------
# Hash + raw content checks
# -----------------------------------------------------------------------------
def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def contains_eicar(path, sha256):
    if sha256 == EICAR_SHA256:
        return True
    try:
        if os.path.getsize(path) > 4096:  # the EICAR file is tiny by design
            return False
        with open(path, "rb") as f:
            return EICAR.encode("ascii") in f.read()
    except OSError:
        return False


# -----------------------------------------------------------------------------
# File-type identification
# -----------------------------------------------------------------------------
def guess_type(path):
    try:
        from oletools import ftguess
        g = ftguess.FileTypeGuesser(path)
        return {
            "name": getattr(g.ftype, "name", "Unknown"),
            "extension": getattr(g.ftype, "extension", None),
            "is_office": bool(g.ftype.container in ("OLE", "OpenXML"))
            if getattr(g.ftype, "container", None) else False,
            "container": getattr(g.ftype, "container", None),
        }
    except Exception as e:  # noqa: BLE001
        return {"name": "Unknown", "error": "{}: {}".format(type(e).__name__, e)}


def is_office_file(path):
    info = guess_type(path)
    if info.get("is_office"):
        return True
    return path.lower().endswith(
        (".doc", ".docm", ".dot", ".dotm", ".xls", ".xlsm", ".xlsb", ".xlt",
         ".xltm", ".ppt", ".pptm", ".pot", ".potm", ".docx", ".xlsx", ".pptx",
         ".rtf", ".mht", ".slk")
    )


# -----------------------------------------------------------------------------
# Office macro analysis (OleID + olevba)
# -----------------------------------------------------------------------------
def analyse_office(path):
    result = {"has_macros": False, "indicators": [], "macro_keywords": [],
              "vba_stomping": False, "flags": {}, "error": None}
    # OleID indicators
    try:
        from oletools.oleid import OleID
        oid = OleID(path)
        for ind in oid.check():
            val = ind.value
            if hasattr(val, "name"):  # RISK enum
                val = val.name
            result["indicators"].append({
                "id": ind.id, "name": ind.name, "value": str(val),
                "risk": getattr(getattr(ind, "risk", None), "name",
                                str(getattr(ind, "risk", ""))),
            })
    except Exception as e:  # noqa: BLE001
        result["error"] = "oleid: {}: {}".format(type(e).__name__, e)

    # olevba macro analysis
    try:
        from oletools.olevba import VBA_Parser
        vp = VBA_Parser(path)
        try:
            if vp.detect_vba_macros():
                result["has_macros"] = True
                counts = {}
                for (kw_type, keyword, desc) in vp.analyze_macros():
                    counts[kw_type] = counts.get(kw_type, 0) + 1
                    result["macro_keywords"].append(
                        {"type": kw_type, "keyword": keyword, "description": desc})
                result["flags"] = counts
            try:
                result["vba_stomping"] = bool(vp.detect_vba_stomping())
            except Exception:  # noqa: BLE001
                pass
        finally:
            vp.close()
    except Exception as e:  # noqa: BLE001
        msg = "olevba: {}: {}".format(type(e).__name__, e)
        result["error"] = (result["error"] + " | " + msg) if result["error"] else msg
    return result


# -----------------------------------------------------------------------------
# PDF structural analysis (pdfid)
# -----------------------------------------------------------------------------
def analyse_pdf(path):
    result = {"keywords": {}, "risky": [], "error": None}
    try:
        from pdfid.pdfid import PDFiD, PDFiD2JSON
        xml = PDFiD(path, allNames=False, extraData=False,
                    disarm=False, force=True)
        data = json.loads(PDFiD2JSON(xml, force=True))
        kw = {}
        try:
            for item in data[0]["pdfid"]["keywords"]["keyword"]:
                kw[item["name"]] = int(item.get("count", 0))
        except (KeyError, IndexError, TypeError):
            pass
        result["keywords"] = {k: v for k, v in kw.items() if v}
        result["risky"] = [k for k in PDF_RISKY_KEYWORDS
                           if kw.get(k, 0) > 0]
    except Exception as e:  # noqa: BLE001
        result["error"] = "pdfid: {}: {}".format(type(e).__name__, e)
    return result


# -----------------------------------------------------------------------------
# VirusTotal hash-only lookup (vt-py)  - opt-in
# -----------------------------------------------------------------------------
class VTRateLimiter:
    """Keeps VirusTotal calls under the free-tier 4 requests / minute limit."""
    def __init__(self, max_per_min=4):
        self.min_interval = 60.0 / max_per_min
        self._last = 0.0

    def wait(self):
        gap = time.monotonic() - self._last
        if gap < self.min_interval:
            time.sleep(self.min_interval - gap)
        self._last = time.monotonic()


def vt_lookup(sha256, rate_limiter=None):
    api_key = os.environ.get("VIRUSTOTAL_API_KEY") or os.environ.get("VT_API_KEY")
    if not api_key:
        return {"performed": False, "reason": "no API key (set VIRUSTOTAL_API_KEY)"}
    try:
        import vt
    except ImportError:
        return {"performed": False, "reason": "vt-py not installed"}
    if rate_limiter:
        rate_limiter.wait()
    try:
        with vt.Client(api_key) as client:
            obj = client.get_object("/files/{}".format(sha256))
            stats = getattr(obj, "last_analysis_stats", {}) or {}
            return {
                "performed": True,
                "found": True,
                "malicious": int(stats.get("malicious", 0)),
                "suspicious": int(stats.get("suspicious", 0)),
                "harmless": int(stats.get("harmless", 0)),
                "undetected": int(stats.get("undetected", 0)),
                "reputation": getattr(obj, "reputation", None),
                "names": (getattr(obj, "names", []) or [])[:5],
            }
    except Exception as e:  # noqa: BLE001
        name = type(e).__name__
        # vt.error.APIError with code NotFoundError => hash unknown to VT
        if "NotFound" in name or "NotFound" in str(e):
            return {"performed": True, "found": False}
        return {"performed": True, "found": None,
                "error": "{}: {}".format(name, e)}


# -----------------------------------------------------------------------------
# Verdict scoring
# -----------------------------------------------------------------------------
def score(report):
    reasons = []
    level = "low"

    def bump(target):
        nonlocal level
        order = ["low", "medium", "high", "critical"]
        if order.index(target) > order.index(level):
            level = target

    if report.get("eicar"):
        bump("critical")
        reasons.append("EICAR antivirus test signature present")

    vt = report.get("virustotal", {})
    if vt.get("performed") and vt.get("found"):
        mal = vt.get("malicious", 0)
        susp = vt.get("suspicious", 0)
        if mal >= 5:
            bump("critical")
            reasons.append("VirusTotal: {} engines flag malicious".format(mal))
        elif mal >= 1:
            bump("high")
            reasons.append("VirusTotal: {} engines flag malicious".format(mal))
        elif susp >= 1:
            bump("medium")
            reasons.append("VirusTotal: {} engines flag suspicious".format(susp))

    office = report.get("office")
    if office:
        if office.get("vba_stomping"):
            bump("high")
            reasons.append("VBA stomping detected (hidden macro source)")
        flags = office.get("flags", {})
        if flags.get("Suspicious") or flags.get("IOC"):
            bump("high")
            reasons.append("Suspicious macro keywords / IOCs found")
        if office.get("has_macros"):
            bump("medium")
            reasons.append("Contains VBA macros ({} keyword hits)".format(
                len(office.get("macro_keywords", []))))
        if flags.get("AutoExec"):
            bump("high")
            reasons.append("Macro auto-executes (AutoExec)")

    pdf = report.get("pdf")
    if pdf and pdf.get("risky"):
        risky = pdf["risky"]
        if "/Launch" in risky or "/JS" in risky or "/JavaScript" in risky \
                or "/OpenAction" in risky:
            bump("high")
        else:
            bump("medium")
        reasons.append("PDF active content: " + ", ".join(risky))

    report["verdict"] = level
    report["risk_score"] = ["low", "medium", "high", "critical"].index(level)
    report["reasons"] = reasons
    return level


# -----------------------------------------------------------------------------
# Triage one file
# -----------------------------------------------------------------------------
def triage_file(path, do_vt=False, rate_limiter=None):
    report = {
        "tool": "triage.py",
        "version": "1.0",
        "timestamp": now_iso(),
        "path": os.path.abspath(path),
    }
    if not os.path.isfile(path):
        report["error"] = "not a file"
        report["verdict"] = "error"
        return report
    try:
        report["size"] = os.path.getsize(path)
        report["sha256"] = sha256_of(path)
        report["filetype"] = guess_type(path)
        report["eicar"] = contains_eicar(path, report["sha256"])

        if is_office_file(path):
            report["office"] = analyse_office(path)
        if path.lower().endswith(".pdf"):
            report["pdf"] = analyse_pdf(path)

        if do_vt:
            report["virustotal"] = vt_lookup(report["sha256"], rate_limiter)
        else:
            report["virustotal"] = {"performed": False, "reason": "--vt not set"}

        score(report)
    except Exception as e:  # noqa: BLE001
        report["error"] = "{}: {}".format(type(e).__name__, e)
        report["traceback"] = traceback.format_exc()
        report["verdict"] = "error"
    return report


# -----------------------------------------------------------------------------
# Pretty printer
# -----------------------------------------------------------------------------
def pretty(report):
    lines = []
    lines.append("FILE     : {}".format(report.get("path")))
    lines.append("SHA-256  : {}".format(report.get("sha256", "-")))
    ft = report.get("filetype", {})
    lines.append("TYPE     : {}".format(ft.get("name", "-")))
    lines.append("VERDICT  : {}".format(str(report.get("verdict", "-")).upper()))
    for r in report.get("reasons", []):
        lines.append("  - {}".format(r))
    if report.get("error"):
        lines.append("ERROR    : {}".format(report["error"]))
    return "\n".join(lines)


# -----------------------------------------------------------------------------
# Watch mode
# -----------------------------------------------------------------------------
def write_log(log_path, report):
    if not log_path:
        return
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = "{}  [TRIAGE] verdict={} sha256={} reasons={} path={}".format(
        ts, report.get("verdict"), report.get("sha256", "-"),
        "; ".join(report.get("reasons", [])) or "none", report.get("path"))
    try:
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except OSError:
        pass


def watch(folder, do_vt, log_path, interval=5):
    seen = set()
    rl = VTRateLimiter()
    print("[watch] triaging new files in {} (Ctrl+C to stop)".format(folder),
          file=sys.stderr)
    os.makedirs(folder, exist_ok=True)
    # prime with existing files so we only report NEW arrivals
    for name in os.listdir(folder):
        seen.add(name)
    while True:
        try:
            for name in os.listdir(folder):
                if name in seen:
                    continue
                seen.add(name)
                full = os.path.join(folder, name)
                if not os.path.isfile(full):
                    continue
                time.sleep(1)  # let the file finish writing
                rep = triage_file(full, do_vt=do_vt, rate_limiter=rl)
                print(json.dumps(rep))
                sys.stdout.flush()
                write_log(log_path, rep)
            time.sleep(interval)
        except KeyboardInterrupt:
            print("[watch] stopped", file=sys.stderr)
            return 0


# -----------------------------------------------------------------------------
def main(argv=None):
    p = argparse.ArgumentParser(description="Static + VirusTotal-hash file triage.")
    p.add_argument("file", nargs="?", help="file to triage")
    p.add_argument("--vt", action="store_true",
                   help="perform a VirusTotal hash-only lookup (needs API key)")
    p.add_argument("--pretty", action="store_true",
                   help="human-readable output instead of JSON")
    p.add_argument("--watch", metavar="FOLDER",
                   help="watch a drop-folder and triage newly-arrived files")
    p.add_argument("--log", metavar="FILE",
                   help="append one-line triage results to this log file")
    args = p.parse_args(argv)

    if args.watch:
        return watch(args.watch, args.vt, args.log)

    if not args.file:
        p.error("a file path is required (or use --watch FOLDER)")

    report = triage_file(args.file, do_vt=args.vt, rate_limiter=VTRateLimiter())
    if args.pretty:
        print(pretty(report))
    else:
        print(json.dumps(report, indent=2))
    write_log(args.log, report)
    return VERDICT_EXIT.get(report.get("verdict"), 1)


if __name__ == "__main__":
    sys.exit(main())

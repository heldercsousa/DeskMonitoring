#!/usr/bin/env python3
"""
parse_netsensor.py - Suricata EVE JSON + Zeek log heuristic analyzer.

Part of the C:\\Sync security ecosystem (Backlog task T083 - out-of-band sensor).

What it does
------------
Reads the logs produced by the out-of-band N100 sensor (Security Onion / standalone
Suricata + Zeek) and emits a JSON summary of suspicious findings that matter under
an assume-breach threat model: C2 beaconing, data exfiltration, DNS tunneling / DGA,
and weak/odd TLS. It is read-only forensic analysis - it never touches the network.

Inputs (any combination; auto-detected by content/extension):
  * Suricata EVE JSON          (eve.json - newline-delimited JSON)
  * Zeek conn.log              (TSV with #fields header, or JSON-lines)
  * Zeek dns.log               (TSV or JSON-lines)
  * Zeek tls.log / ssl.log     (TSV or JSON-lines)

Heuristics
----------
  BEACON   regular, low-jitter repeated connections to the same dest:port
           (coefficient of variation of inter-arrival gaps below a threshold)
  EXFIL    large cumulative outbound (orig->resp) bytes to a single dest
  DNS-DGA  long / high-entropy query names, or many unique subdomains under one
           parent, or a high NXDOMAIN ratio (classic DNS-tunnel / DGA markers)
  TLS-WEAK self-signed / unestablished / validation-failed certs, empty SNI
  ALERT    Suricata IDS alerts passed straight through (highest signal)

Safety / scope
--------------
  * Pure stdlib (json, math, statistics, collections, argparse) - NO pip install,
    so it runs anywhere, including the air-gapped sensor itself.
  * Analyzes logs that were captured OFF the compromised host. Treat the laptop's
    own logs as untrusted; this tool is meant for the out-of-band feed.
  * Heuristic, not authoritative: findings are leads to investigate, not verdicts.

Usage
-----
  python parse_netsensor.py --eve eve.json
  python parse_netsensor.py --conn conn.log --dns dns.log --tls tls.log
  python parse_netsensor.py --eve eve.json --conn conn.log --pretty
  python parse_netsensor.py --eve eve.json --out findings.json

Exit code
---------
  0  no findings
  2  only low/medium findings
  3  at least one high/critical finding (IDS alert, strong beacon, big exfil)
  1  input/parse error
"""

import argparse
import json
import math
import os
import statistics
import sys
from collections import defaultdict

# ---- tunable thresholds -------------------------------------------------

BEACON_MIN_HITS = 6          # need this many connections to call it periodic
BEACON_MAX_CV = 0.25         # coeff. of variation of gaps below this => regular
BEACON_MIN_INTERVAL = 5      # ignore sub-5s chatter (noisy, not classic C2)

EXFIL_BYTES_HIGH = 100 * 1024 * 1024   # 100 MB outbound to one dest => high
EXFIL_BYTES_MED = 10 * 1024 * 1024     # 10 MB => medium

DNS_NAME_LONG = 50           # query label length suggesting tunneling
DNS_ENTROPY_HIGH = 3.8       # Shannon entropy (bits/char) suggesting DGA/encoding
DNS_SUBDOMAIN_MANY = 50      # unique subdomains under one parent => tunnel candidate
DNS_NXDOMAIN_RATIO = 0.5     # NXDOMAIN share (with enough volume) => DGA candidate
DNS_MIN_VOLUME = 20          # minimum queries before ratio/subdomain heuristics fire


# ---- generic log readers ------------------------------------------------

def _read_json_lines(path):
    """Yield dict records from a newline-delimited JSON file."""
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                continue


def _read_zeek(path):
    """
    Yield dict records from a Zeek log, supporting both formats:
      * classic TSV with '#fields' / '#separator' headers
      * JSON-lines (Zeek with @load policy/tuning/json-logs)
    """
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        first = fh.readline()
        if not first:
            return
        stripped = first.lstrip()
        if stripped.startswith("{"):
            # JSON-lines Zeek
            try:
                yield json.loads(stripped)
            except json.JSONDecodeError:
                pass
            for line in fh:
                line = line.strip()
                if line:
                    try:
                        yield json.loads(line)
                    except json.JSONDecodeError:
                        continue
            return

        # TSV Zeek: parse directives, then rows
        sep = "\t"
        fields = None
        unset = "-"
        # process the first line then the rest uniformly
        lines = [first] + fh.readlines()
        for line in lines:
            line = line.rstrip("\n")
            if line.startswith("#"):
                if line.startswith("#separator"):
                    val = line.split(" ", 1)[1].strip() if " " in line else "\\x09"
                    if val in (r"\x09", r"\t", ""):
                        sep = "\t"
                    elif val.startswith(r"\x"):
                        try:
                            sep = chr(int(val[2:], 16))
                        except ValueError:
                            sep = "\t"
                    else:
                        sep = val
                    if not sep:
                        sep = "\t"
                elif line.startswith("#fields"):
                    fields = line.split(sep)[1:]
                elif line.startswith("#unset_field"):
                    unset = line.split(sep, 1)[1].strip() if sep in line else line.split(" ", 1)[1].strip()
                continue
            if fields is None:
                continue
            parts = line.split(sep)
            rec = {}
            for i, name in enumerate(fields):
                rec[name] = parts[i] if i < len(parts) else unset
            yield rec


def _to_float(val):
    try:
        if val in (None, "-", "(empty)", ""):
            return None
        return float(val)
    except (TypeError, ValueError):
        return None


def _shannon_entropy(s):
    if not s:
        return 0.0
    counts = defaultdict(int)
    for ch in s:
        counts[ch] += 1
    n = len(s)
    return -sum((c / n) * math.log2(c / n) for c in counts.values())


def _parent_domain(name):
    """Return the registrable-ish parent (last two labels) of a domain."""
    name = (name or "").rstrip(".").lower()
    parts = [p for p in name.split(".") if p]
    if len(parts) <= 2:
        return name
    return ".".join(parts[-2:])


# ---- normalization: turn each source into common event dicts ------------

def load_events(args):
    """
    Returns three lists of normalized dicts:
      conns:  {ts, src, dst, dport, proto, obytes, rbytes}
      dnsq:   {ts, query, rcode}
      tlsx:   {ts, sni, subject, issuer, validation, established}
    plus a list of raw Suricata alerts.
    """
    conns, dnsq, tlsx, alerts = [], [], [], []

    # --- Suricata EVE JSON ---
    if args.eve:
        for ev in _read_json_lines(args.eve):
            etype = ev.get("event_type")
            ts = ev.get("timestamp")
            if etype == "alert":
                a = ev.get("alert", {})
                alerts.append({
                    "ts": ts,
                    "src": ev.get("src_ip"),
                    "dst": ev.get("dest_ip"),
                    "dport": ev.get("dest_port"),
                    "signature": a.get("signature"),
                    "category": a.get("category"),
                    "severity": a.get("severity"),
                })
            elif etype == "flow":
                fl = ev.get("flow", {})
                conns.append({
                    "ts": _epoch(ts),
                    "src": ev.get("src_ip"),
                    "dst": ev.get("dest_ip"),
                    "dport": ev.get("dest_port"),
                    "proto": ev.get("proto"),
                    "obytes": fl.get("bytes_toserver") or 0,
                    "rbytes": fl.get("bytes_toclient") or 0,
                })
            elif etype == "dns":
                d = ev.get("dns", {})
                if d.get("type") in ("query", None) and d.get("rrname"):
                    dnsq.append({
                        "ts": _epoch(ts),
                        "query": d.get("rrname"),
                        "rcode": d.get("rcode"),
                    })
            elif etype == "tls":
                t = ev.get("tls", {})
                tlsx.append({
                    "ts": _epoch(ts),
                    "sni": t.get("sni"),
                    "subject": t.get("subject"),
                    "issuer": t.get("issuerdn"),
                    "validation": None,
                    "established": True,
                })

    # --- Zeek conn.log ---
    if args.conn:
        for r in _read_zeek(args.conn):
            conns.append({
                "ts": _to_float(r.get("ts")),
                "src": r.get("id.orig_h") or r.get("orig_h"),
                "dst": r.get("id.resp_h") or r.get("resp_h"),
                "dport": _coerce_port(r.get("id.resp_p") or r.get("resp_p")),
                "proto": r.get("proto"),
                "obytes": _to_float(r.get("orig_bytes")) or 0,
                "rbytes": _to_float(r.get("resp_bytes")) or 0,
            })

    # --- Zeek dns.log ---
    if args.dns:
        for r in _read_zeek(args.dns):
            q = r.get("query")
            if q:
                dnsq.append({
                    "ts": _to_float(r.get("ts")),
                    "query": q,
                    "rcode": r.get("rcode_name") or r.get("rcode"),
                })

    # --- Zeek tls.log / ssl.log ---
    if args.tls:
        for r in _read_zeek(args.tls):
            est = r.get("established")
            tlsx.append({
                "ts": _to_float(r.get("ts")),
                "sni": r.get("server_name"),
                "subject": r.get("subject"),
                "issuer": r.get("issuer"),
                "validation": r.get("validation_status"),
                "established": (est in ("T", True, "true")),
            })

    return conns, dnsq, tlsx, alerts


def _epoch(ts):
    """Best-effort ISO8601 -> epoch seconds (for Suricata timestamps)."""
    if ts is None:
        return None
    if isinstance(ts, (int, float)):
        return float(ts)
    s = str(ts)
    # Suricata: 2026-06-29T13:45:01.123456+0000
    try:
        import datetime
        s2 = s.replace("Z", "+00:00")
        # normalise +0000 -> +00:00 for fromisoformat
        if len(s2) >= 5 and (s2[-5] in "+-") and s2[-3] != ":":
            s2 = s2[:-2] + ":" + s2[-2:]
        return datetime.datetime.fromisoformat(s2).timestamp()
    except (ValueError, ImportError):
        return None


def _coerce_port(val):
    try:
        return int(val)
    except (TypeError, ValueError):
        return val


# ---- heuristics ---------------------------------------------------------

def detect_beacons(conns):
    findings = []
    groups = defaultdict(list)
    for c in conns:
        if c["ts"] is None or not c["dst"]:
            continue
        groups[(c["src"], c["dst"], c["dport"])].append(c["ts"])

    for (src, dst, dport), times in groups.items():
        if len(times) < BEACON_MIN_HITS:
            continue
        times.sort()
        gaps = [b - a for a, b in zip(times, times[1:]) if (b - a) >= BEACON_MIN_INTERVAL]
        if len(gaps) < BEACON_MIN_HITS - 1:
            continue
        mean = statistics.mean(gaps)
        if mean <= 0:
            continue
        stdev = statistics.pstdev(gaps)
        cv = stdev / mean
        if cv <= BEACON_MAX_CV:
            sev = "high" if (cv <= BEACON_MAX_CV / 2 and len(times) >= BEACON_MIN_HITS * 2) else "medium"
            findings.append({
                "type": "BEACON",
                "severity": sev,
                "src": src, "dst": dst, "dport": dport,
                "hits": len(times),
                "interval_s": round(mean, 1),
                "jitter_cv": round(cv, 3),
                "note": "regular low-jitter repeats - possible C2 beacon",
            })
    return findings


def detect_exfil(conns):
    findings = []
    totals = defaultdict(float)
    for c in conns:
        if c["dst"]:
            totals[(c["src"], c["dst"])] += c.get("obytes") or 0
    for (src, dst), obytes in totals.items():
        if obytes >= EXFIL_BYTES_MED:
            sev = "high" if obytes >= EXFIL_BYTES_HIGH else "medium"
            findings.append({
                "type": "EXFIL",
                "severity": sev,
                "src": src, "dst": dst,
                "out_bytes": int(obytes),
                "out_mb": round(obytes / (1024 * 1024), 1),
                "note": "large cumulative outbound volume to one destination",
            })
    return findings


def detect_dns(dnsq):
    findings = []
    parent_subs = defaultdict(set)
    parent_total = defaultdict(int)
    parent_nx = defaultdict(int)

    for q in dnsq:
        name = (q.get("query") or "").rstrip(".").lower()
        if not name:
            continue
        labels = name.split(".")
        first = labels[0] if labels else ""
        # per-query: long or high-entropy first label
        if len(first) >= DNS_NAME_LONG:
            findings.append({
                "type": "DNS-DGA", "severity": "medium",
                "query": name, "note": "very long DNS label - tunneling candidate",
            })
        elif first and _shannon_entropy(first) >= DNS_ENTROPY_HIGH and len(first) >= 12:
            findings.append({
                "type": "DNS-DGA", "severity": "low",
                "query": name,
                "entropy": round(_shannon_entropy(first), 2),
                "note": "high-entropy DNS label - DGA/encoded candidate",
            })
        parent = _parent_domain(name)
        parent_total[parent] += 1
        if len(labels) > 2:
            parent_subs[parent].add(".".join(labels[:-2]))
        rc = str(q.get("rcode") or "").upper()
        if rc in ("NXDOMAIN", "3"):
            parent_nx[parent] += 1

    for parent, total in parent_total.items():
        if total < DNS_MIN_VOLUME:
            continue
        nsub = len(parent_subs.get(parent, ()))
        if nsub >= DNS_SUBDOMAIN_MANY:
            findings.append({
                "type": "DNS-DGA", "severity": "high",
                "parent": parent, "unique_subdomains": nsub, "queries": total,
                "note": "many unique subdomains under one parent - DNS tunnel candidate",
            })
        nx = parent_nx.get(parent, 0)
        if total >= DNS_MIN_VOLUME and (nx / total) >= DNS_NXDOMAIN_RATIO:
            findings.append({
                "type": "DNS-DGA", "severity": "medium",
                "parent": parent, "nxdomain": nx, "queries": total,
                "nx_ratio": round(nx / total, 2),
                "note": "high NXDOMAIN ratio - DGA candidate",
            })
    return findings


def detect_tls(tlsx):
    findings = []
    for t in tlsx:
        sev = None
        reason = None
        val = (t.get("validation") or "").lower()
        subject = t.get("subject") or ""
        issuer = t.get("issuer") or ""
        if val and val not in ("ok", "-", ""):
            sev, reason = "medium", "certificate validation failed: %s" % val
        elif subject and issuer and subject == issuer:
            sev, reason = "medium", "self-signed certificate (subject == issuer)"
        elif t.get("sni") in (None, "", "-") and t.get("established"):
            sev, reason = "low", "established TLS with empty SNI"
        if sev:
            findings.append({
                "type": "TLS-WEAK", "severity": sev,
                "sni": t.get("sni"), "subject": subject or None,
                "issuer": issuer or None, "note": reason,
            })
    return findings


def alerts_to_findings(alerts):
    out = []
    severity_map = {1: "high", 2: "medium", 3: "low"}
    for a in alerts:
        sev = severity_map.get(a.get("severity"), "high")
        out.append({
            "type": "ALERT", "severity": sev,
            "src": a.get("src"), "dst": a.get("dst"), "dport": a.get("dport"),
            "signature": a.get("signature"), "category": a.get("category"),
            "note": "Suricata IDS alert",
        })
    return out


# ---- main ---------------------------------------------------------------

def main(argv=None):
    p = argparse.ArgumentParser(description="Suricata EVE / Zeek heuristic analyzer (T083)")
    p.add_argument("--eve", help="Suricata eve.json (newline-delimited JSON)")
    p.add_argument("--conn", help="Zeek conn.log (TSV or JSON-lines)")
    p.add_argument("--dns", help="Zeek dns.log (TSV or JSON-lines)")
    p.add_argument("--tls", help="Zeek tls.log/ssl.log (TSV or JSON-lines)")
    p.add_argument("--out", help="write JSON summary to this file (default stdout)")
    p.add_argument("--pretty", action="store_true", help="human-readable instead of raw JSON")
    args = p.parse_args(argv)

    if not any([args.eve, args.conn, args.dns, args.tls]):
        p.error("supply at least one of --eve / --conn / --dns / --tls")

    for path in (args.eve, args.conn, args.dns, args.tls):
        if path and not os.path.isfile(path):
            sys.stderr.write("ERROR: no such file: %s\n" % path)
            return 1

    try:
        conns, dnsq, tlsx, alerts = load_events(args)
    except OSError as exc:
        sys.stderr.write("ERROR: %s\n" % exc)
        return 1

    findings = []
    findings += alerts_to_findings(alerts)
    findings += detect_beacons(conns)
    findings += detect_exfil(conns)
    findings += detect_dns(dnsq)
    findings += detect_tls(tlsx)

    sev_rank = {"low": 1, "medium": 2, "high": 3, "critical": 4}
    findings.sort(key=lambda f: sev_rank.get(f.get("severity"), 0), reverse=True)

    counts = defaultdict(int)
    for f in findings:
        counts[f.get("severity", "unknown")] += 1

    summary = {
        "tool": "parse_netsensor.py",
        "task": "T083",
        "inputs": {k: getattr(args, k) for k in ("eve", "conn", "dns", "tls") if getattr(args, k)},
        "counts": {
            "events_conn": len(conns),
            "events_dns": len(dnsq),
            "events_tls": len(tlsx),
            "ids_alerts": len(alerts),
        },
        "findings_by_severity": dict(counts),
        "findings": findings,
    }

    text = _render_pretty(summary) if args.pretty else json.dumps(summary, indent=2)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as fh:
            fh.write(text + "\n")
    else:
        print(text)

    if counts.get("high") or counts.get("critical"):
        return 3
    if findings:
        return 2
    return 0


def _render_pretty(summary):
    lines = []
    lines.append("=== parse_netsensor (T083) ===")
    c = summary["counts"]
    lines.append("events: conn=%d dns=%d tls=%d ids_alerts=%d" %
                 (c["events_conn"], c["events_dns"], c["events_tls"], c["ids_alerts"]))
    if not summary["findings"]:
        lines.append("no findings")
        return "\n".join(lines)
    lines.append("findings by severity: %s" % summary["findings_by_severity"])
    lines.append("-" * 60)
    for f in summary["findings"]:
        extra = " ".join("%s=%s" % (k, v) for k, v in f.items()
                         if k not in ("type", "severity", "note"))
        lines.append("[%-8s] %-9s %s" % (f["type"], f["severity"], f.get("note", "")))
        if extra:
            lines.append("           %s" % extra)
    return "\n".join(lines)


if __name__ == "__main__":
    sys.exit(main())

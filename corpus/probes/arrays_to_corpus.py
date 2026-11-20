#!/usr/bin/env python3
"""Build corpus/cases/arrays.json from real-Excel probe results.

The expected values are copied verbatim from arrays.results.json (produced by
run_probes.ps1 against desktop Excel); this script never computes an expected value.
Usage: python3 corpus/probes/arrays_to_corpus.py
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RESULTS = [
    os.path.join(ROOT, "corpus/probes/arrays.results.json"),
]
OUT = os.path.join(ROOT, "corpus/cases/arrays.json")

# Entry-level rejects (Excel 1004) and two probes outside the authoritative batch:
# p014/p015: Excel treats `SUM (` as #NAME?; the engine intentionally accepts it
#           as a function call (user requirement), documented as a divergence.
# p126: dynamic INDEX(A1:C3,0,0) written into C3 overwrites the anchor; Excel's
#       cached value is a circular 0, while the probe is not a stable semantic.
SKIP = {"p014", "p015", "p126"}
UNSUPPORTED = re.compile(r"\b(SEQUENCE|OFFSET|INDIRECT)\s*\(", re.I)

def parse_cell(spec):
    if spec == "blank":
        return None
    if spec.startswith("n:"):
        return float(spec[2:])
    if spec.startswith("t:"):
        return spec[2:]
    if spec.startswith("b:"):
        return bool(int(spec[2:]))
    if spec.startswith("e:"):
        return {"error": spec[2:]}
    if spec.startswith("f2:"):
        return {"formula": spec[3:]}
    if spec.startswith("f:"):
        return {"formula": spec[2:]}
    raise ValueError("bad cell spec: " + spec)

def conv_val(v):
    t, x = v.get("t"), v.get("v")
    if t == "number": return {"type": "number", "value": x}
    if t == "text": return {"type": "text", "value": x}
    if t == "bool": return {"type": "bool", "value": bool(x)}
    if t == "error": return {"type": "error", "value": x}
    if t == "blank": return {"type": "blank", "value": None}
    raise ValueError("bad value: %r" % (v,))

def main():
    records, seen = [], set()
    for path in RESULTS:
        with open(path, encoding="utf-8-sig") as f:
            data = json.load(f)
        for r in data:
            rid = r["id"]
            if rid in SKIP or "value" not in r or r.get("entered") is None:
                continue
            if UNSUPPORTED.search(r["formula"]):
                continue
            grid, ok = {}, True
            for part in r.get("setup", "").split(";"):
                if not part:
                    continue
                if "=" not in part:
                    ok = False
                    break
                addr, spec = part.split("=", 1)
                try:
                    val = parse_cell(spec)
                except ValueError:
                    ok = False
                    break
                if isinstance(val, dict) and "formula" in val and UNSUPPORTED.search(val["formula"]):
                    ok = False
                    break
                if val is not None:
                    grid[addr] = val
            if not ok:
                continue
            val = r["value"]
            rec = {
                "id": "probe-" + rid,
                "formula": r["formula"],
                "grid": grid,
                "expected": conv_val(val) if val.get("t") != "array" else None,
                "tags": ["probe", r["mode"]],
                "source": "excel-desktop",
                "notes": "real Excel probe %s; anchor %s" % (rid, r["anchor"]),
            }
            if val.get("t") == "array":
                rows, cols = val["rows"], val["cols"]
                rec["expected"] = {
                    "type": "range", "rows": rows, "cols": cols,
                    "values": [conv_val(c) for row in val["v"] for c in row],
                }
                rec["array"] = {
                    "kind": "cse" if r["mode"] == "cse" else "dynamic",
                    "anchor": r["anchor"], "rows": rows, "cols": cols,
                }
                rec["tags"].append("array")
            elif r["mode"] != "normal":
                rec["array"] = {"kind": r["mode"], "anchor": r["anchor"], "rows": 1, "cols": 1}
            else:
                rec["anchor"] = r["anchor"]
            if r["mode"] in ("cse", "dynamic"):
                rec["tags"].append("array")
            if " B" in r["formula"] and " " in r["formula"]:
                rec["tags"].append("intersection")
            if r["formula"].startswith("=SUM(") and "(" in r["formula"]:
                rec["tags"].append("aggregate")
            if rid not in seen:
                seen.add(rid)
                records.append(rec)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump({"schema": "mooncalc-corpus/1", "records": records}, f, ensure_ascii=False, separators=(",", ":"))
    print("wrote", OUT, "records", len(records))

if __name__ == "__main__":
    main()

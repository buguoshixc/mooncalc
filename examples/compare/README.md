# mbtexcel differential bench

Standalone measurement adapter for the MoonCalc answer-key corpus. It runs every
record in `corpus/cases/` through **moonbitlang/mbtexcel** and writes a bucketed
deviation report to `corpus/reports/mbtexcel.json`.

This package deliberately does **not** import `buguoshixc/mooncalc` and does not
share code with it. The bucketing rules from `src/codec/bench.mbt` are
re-implemented here, so the comparison is an independent second implementation.

## Pinned versions

| Component | Version |
| --- | --- |
| `moonbitlang/mbtexcel` | `0.3.2` |
| `moonbitlang/x` | `0.5.6` |
| Moon toolchain | `0.1.20261104 (940aa18 2026-11-04)` |
| Corpus schema | `mooncalc-corpus/1`, 8 files, 1,169 records |

The dependency versions are pinned in `moon.mod`; the report also records
`engine.version` and `engine.moon`.

## Build and rerun

```sh
export PATH=/home/buguoshixc/.moon/bin:$PATH
cd examples/compare
moon check --target native
moon run --target native . -- \
  --corpus ../../corpus/cases \
  --report ../../corpus/reports/mbtexcel.json
```

Optional flags: `--tol <relative tolerance>` (default `1e-9`) and
`--clock-tol <absolute clock tolerance>` (default `1e-6`). The command is
reproducible: bucket counts and pass/fail totals are identical across runs. The
only run-to-run variation is the recorded `actual` value of clock records, which
is the live host clock by construction.

## Method

For every record the adapter:

1. creates a fresh `@xlsx.Workbook` with a private main sheet
   (`MoonCalcMain`, renamed only if the record itself uses that name);
2. writes the record's `grid` cells: JSON number → `Numeric`, string → `String`,
   `true`/`false` → `Bool`, `null` → blank (cell omitted), `{"formula": ...}` →
   formula text, `{"error": ...}` → `Error` string; `SHEET!A1` keys create the
   named sheet, bare `A1` keys go to the main sheet;
3. writes the candidate formula to `ZZ1` verbatim (a leading `=` is preserved;
   mbtexcel strips it when parsing);
4. calls `calc_cell_typed("MoonCalcMain", "ZZ1")`, which evaluates the formula
   on demand;
5. maps the typed result to one of number / text / bool / error / blank
   (`None` is blank) and compares it with `expected` using the bucket order
   below.

Blank is normalised to numeric `0` for comparison (consistent with the
MoonCalc harness). Error values are compared by their `#...#` string name.

## Buckets

The classification order mirrors `src/codec/bench.mbt`:

| Bucket | Meaning |
| --- | --- |
| `match` | exact value (and type) equality |
| `excel-precision` | numbers differ by relative error ≤ `1e-14` (pass) |
| `clock-tolerance` | clock-tagged and absolute difference ≤ `1e-6` (pass); unreachable here because clock records are diverted |
| `numeric-tolerance` | numbers differ by relative error < `--tol` (fail) |
| `value-mismatch` | same type, different value |
| `type-mismatch` | different types |
| `surrogate-representation` | text equal after surrogate normalisation (pass) |
| `parse-error` | mbtexcel could not parse/evaluate the formula (includes `InvalidXml` from the parser) |
| `clock-no-injection` | clock-tagged record, attributed separately (see below) |

`rel_diff(a, b) = |a - b| / max(|a|, |b|)`, and a zero scale counts as a match.
`by_tag` counts one record once per tag occurrence, so tag totals can exceed the
record count; `by_source` partitions the 1,169 records.

## Clock records (33)

mbtexcel 0.3.2 exposes no clock injection: `NOW()` / `TODAY()` read the host
clock through `@env.now()`. The corpus supplies a `now` serial, but there is no
API to install it, so **all 33 clock-tagged records** are put in
`clock-no-injection` and are **not** counted as matches, even when the host
value happens to agree. The report's `attribution.clock.exact_matches_if_compared`
is diagnostic only; it does not change the bucket or pass count.

## Iteration records (18)

17 records carry `iter` settings (`iter-off-control-0016` carries only the tag).
The adapter stores `max_iterations` / `max_change` with
`Workbook::set_calc_props`, but mbtexcel's `calc_cell_typed` does not consult
`CalcPropsOptions`: evaluation is single-pass. Iteration records are therefore
evaluated once and reported exactly as observed (typically `#CALC!` for
circular references); the report states this in `attribution.iteration`.

## Methodology difference

The corpus answer key was captured from real Excel desktop behaviour; MoonCalc's
own report is all-green against it. mbtexcel aims at excelize-style parity, not
Excel-desktop parity, so the deviation rate here measures **engine semantics**,
not adapter correctness. Examples visible in the report: `DATE` year-offset
handling, 1900 leap-bug edge cases, date-text coercion, boolean cells inside
`SUM` ranges, case-sensitive `SUMIF`, and error literals used as formula
arguments (rejected by mbtexcel's parser). These are recorded as observed, not
worked around.

## Known limitations

- No clock injection (all clock records diverted, see above).
- Iteration properties are inert in `calc_cell_typed`.
- Error literals as formula arguments (`=COUNT(#N/A)`, `=IFERROR(1/0,#N/A)`,
  `=XLOOKUP(#N/A,...)`) fail at parse time and land in `parse-error`.
- The adapter reads JSON records only; it does not round-trip `.xlsx` files.
- Blank/0 normalisation and error-name string comparison inherit the MoonCalc
  harness convention.
- Native target only (the bench touches the filesystem).

## Report

`corpus/reports/mbtexcel.json` is authoritative and contains:
`engine` (name/version/moon), `corpus` (total and per-file counts), `total`,
`passed`, `failed`, `rate`, `tol`, `clock_tol`, `tolerances`, `attribution`
(clock/iteration), `buckets`, `by_source`, `by_tag`, `failures` (every
non-passed record with formula, tags, expected/actual, bucket and detail), and
`rerun` (the exact command above).

Snapshot for the pinned versions: **1,169 records, 938 passed, 231 failed
(rate 0.8024)** — `match` 934, `excel-precision` 3,
`surrogate-representation` 1, `value-mismatch` 105, `type-mismatch` 89,
`parse-error` 4, `clock-no-injection` 33. Bucket sum = 1,169 = `total`.

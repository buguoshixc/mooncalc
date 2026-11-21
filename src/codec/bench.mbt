// Pure bench engine: run records, classify diffs, aggregate.
// Excel is the only authoritative judge; manual sources are provisional.

/// 单条用例的对照结果。
pub(all) struct CaseResult {
  /// 用例标识。
  id : String
  /// 被求值的公式。
  formula : String
  /// 来源。
  source : String
  /// 标签。
  tags : Array[String]
  /// 是否通过（含 clock-tolerance / excel-precision 两个披露桶）。
  passed : Bool
  /// 归因桶：match / clock-tolerance / excel-precision / numeric-tolerance /
  /// value-mismatch / type-mismatch / parse-error。
  bucket : String
  /// 期望值 JSON。
  expected : Json
  /// 实际值 JSON。
  actual : Json
  /// 差异说明（通过且精确命中时为空）。
  detail : String
} derive(Show, Debug)

/// 语料对照聚合报告。
pub(all) struct BenchReport {
  /// 参与对照的用例数。
  total : Int
  /// 通过数。
  passed : Int
  /// 数值相对差容差（低于它但高于 1e-14 仍计失败，单列 numeric-tolerance）。
  tol : Double
  /// clock 用例的绝对天数容差。
  clock_tol : Double
  /// 逐条结果。
  results : Array[CaseResult]
  /// 按来源聚合（总数, 通过数）。
  by_source : Map[String, (Int, Int)]
  /// 按标签聚合（总数, 通过数）。
  by_tag : Map[String, (Int, Int)]
  /// 各归因桶计数。
  buckets : Map[String, Int]
}

fn bump(m : Map[String, (Int, Int)], key : String, passed : Bool) -> Unit {
  let (t, p) = match m.get(key) {
    Some(v) => v
    None => (0, 0)
  }
  m[key] = (t + 1, if passed { p + 1 } else { p })
}

// Corpus numbers are serialized by Excel/VBA with at most 15 significant
// decimal digits, so a relative difference below ~1e-14 is a representation
// artefact (15-digit round-trip), not a behavioural difference.
let excel_precision_tol : Double = 1.0e-14

fn rel_diff(a : Double, b : Double) -> Double {
  let aa = a.abs()
  let ab = b.abs()
  let scale = if aa > ab { aa } else { ab }
  if scale == 0.0 { 0.0 } else { (a - b).abs() / scale }
}

fn compare_case(rec : CaseRecord, tol : Double, clock_tol : Double) -> CaseResult {
  let is_clock = rec.tags.contains("clock")
  let expected_json = value_to_json(rec.expected)
  let base : CaseResult = {
    id: rec.id,
    formula: rec.formula,
    source: rec.source,
    tags: rec.tags,
    passed: false,
    bucket: "",
    expected: expected_json,
    actual: Json::null(),
    detail: "",
  }
  if rec.setup_arrays.length() > 0 {
    let actual = try actual_with_setup_arrays(rec) catch {
      CodecError(msg) =>
        return {
          ..base,
          passed: false,
          bucket: "parse-error",
          actual: Json::null(),
          detail: msg,
        }
    }
    return compare_actual(rec, actual, tol, clock_tol, is_clock, base)
  }
  let evaluated = match rec.iter {
    Some(it) =>
      @facade.eval_formula_iterative(rec.formula, rec.grid, { now: rec.now }, it)
    None =>
      match rec.anchor {
        Some(a) => {
          // 复刻 Excel 探针：公式写在宿主格（可能因此与引用区域成环）。
          let _ = try @syntax.parse(rec.formula) catch {
            @syntax.ParseError(msg) =>
              return {
                ..base,
                passed: false,
                bucket: "parse-error",
                actual: Json::null(),
                detail: msg,
              }
          }
          rec.grid.cells[a] = @facade.Cell::Formula(rec.formula)
          Ok(@facade.eval_at_key(a, rec.grid, { now: rec.now }))
        }
        None => @facade.eval_formula(rec.formula, rec.grid, { now: rec.now })
      }
  }
  let out = match evaluated {
    Ok(o) => o
    Err(@syntax.ParseError(msg)) =>
      return {
        ..base,
        passed: false,
        bucket: "parse-error",
        actual: Json::null(),
        detail: msg,
      }
  }
  if rec.array is Some(spec) {
    let actual = try actual_for_array(rec, spec) catch {
      CodecError(msg) =>
        return {
          ..base,
          passed: false,
          bucket: "parse-error",
          actual: Json::null(),
          detail: msg,
        }
    }
    return compare_actual(rec, actual, tol, clock_tol, is_clock, base)
  }
  let actual = match out.value {
    Range(r) => if r.cells.length() == 1 { r.cells[0] } else { out.value }
    v => v
  }
  compare_actual(rec, actual, tol, clock_tol, is_clock, base)
}

fn compare_scalar(
  expected : Value,
  actual : Value,
  tol : Double,
  clock_tol : Double,
  is_clock : Bool
) -> (Bool, String, String) {
  match (expected, actual) {
    (Num(a), Num(b)) =>
      if a == b {
        (true, "match", "")
      } else if is_clock && (a - b).abs() <= clock_tol {
        (true, "clock-tolerance", "within clock tolerance")
      } else if rel_diff(a, b) <= excel_precision_tol {
        (
          true,
          "excel-precision",
          "within 15-significant-digit Excel representation",
        )
      } else if rel_diff(a, b) < tol {
        (false, "numeric-tolerance", "relative diff " + rel_diff(a, b).to_string())
      } else {
        (false, "value-mismatch", "")
      }
    (Text(a), Text(b)) =>
      if a == b {
        (true, "match", "")
      } else if normalize_surrogates(a) == normalize_surrogates(b) {
        (
          true,
          "surrogate-representation",
          "lone surrogate serialized as U+FFFD by the VBA answer key",
        )
      } else {
        (false, "value-mismatch", "")
      }
    (Bool(a), Bool(b)) =>
      if a == b { (true, "match", "") } else { (false, "value-mismatch", "") }
    (Err(a), Err(b)) =>
      if a == b { (true, "match", "") } else { (false, "value-mismatch", "") }
    (Blank, Blank) => (true, "match", "")
    _ =>
      (
        false,
        "type-mismatch",
        "expected " + expected.type_name() + ", got " + actual.type_name(),
      )
  }
}

fn compare_actual(
  rec : CaseRecord,
  actual : Value,
  tol : Double,
  clock_tol : Double,
  is_clock : Bool,
  base : CaseResult
) -> CaseResult {
  let (passed, bucket, detail) = match (rec.expected, actual) {
    (Range(e), Range(a)) => {
      if e.rows != a.rows || e.cols != a.cols {
        (
          false,
          "value-mismatch",
          "range shape expected " + e.rows.to_string() + "x" +
          e.cols.to_string() + ", got " + a.rows.to_string() + "x" +
          a.cols.to_string(),
        )
      } else {
        let mut ok = true
        let mut why = ""
        let mut first_bucket = "match"
        for i in 0..<e.cells.length() {
          let (p, b, d) = compare_scalar(e.cells[i], a.cells[i], tol, clock_tol, is_clock)
          if !p {
            ok = false
            why = "cell " + (i / e.cols).to_string() + "," + (i % e.cols).to_string() +
              ": " + d
            first_bucket = b
            break
          } else if b != "match" && first_bucket == "match" {
            first_bucket = b
          }
        }
        (ok, first_bucket, why)
      }
    }
    _ => compare_scalar(rec.expected, actual, tol, clock_tol, is_clock)
  }
  { ..base, passed, bucket, actual: value_to_json(actual), detail }
}

fn actual_for_array(rec : CaseRecord, spec : CaseArray) -> Value raise CodecError {
  let layout = @facade.new_array_layout()
  if spec.kind == "cse" {
    layout.set_cse(spec.anchor, rec.formula, spec.rows, spec.cols)
  } else {
    layout.set_dynamic(spec.anchor, rec.formula)
  }
  let out = @facade.recalc_arrays(rec.grid, layout, { now: rec.now })
  if out.parse_errors.length() > 0 {
    raise CodecError(out.parse_errors[0].1)
  }
  match rec.expected {
    Range(_) => {
      let (sheet, text) = @value.split_key(spec.anchor)
      let host = match @value.parse_addr(text) {
        Some(a) => a
        None => raise CodecError("invalid array anchor: " + spec.anchor)
      }
      let cells : Array[Value] = []
      for dr in 0..<spec.rows {
        for dc in 0..<spec.cols {
          let a : @value.CellAddr = {
            row: host.row + dr,
            col: host.col + dc,
            abs_row: false,
            abs_col: false,
          }
          let key = @value.sheet_key(sheet, a)
          cells.push(match out.values.get(key) {
            Some(v) => v
            None => Value::Blank
          })
        }
      }
      Value::Range(@value.RangeValue::array(spec.rows, spec.cols, cells))
    }
    _ =>
      match out.cells.get(spec.anchor) {
        Some(o) => o.value
        None => Value::Blank
      }
  }
}

fn actual_with_setup_arrays(rec : CaseRecord) -> Value raise CodecError {
  let layout = @facade.new_array_layout()
  for spec in rec.setup_arrays {
    if spec.kind == "cse" {
      layout.set_cse(spec.anchor, spec.formula, spec.rows, spec.cols)
    } else {
      layout.set_dynamic(spec.anchor, spec.formula)
    }
  }
  match rec.array {
    Some(main) =>
      if main.kind == "cse" {
        layout.set_cse(main.anchor, rec.formula, main.rows, main.cols)
      } else {
        layout.set_dynamic(main.anchor, rec.formula)
      }
    None =>
      match rec.anchor {
        Some(a) => rec.grid.cells[a] = @facade.Cell::Formula(rec.formula)
        None => raise CodecError("setupArrays requires anchor")
      }
  }
  let out = @facade.recalc_arrays(rec.grid, layout, { now: rec.now })
  if out.parse_errors.length() > 0 {
    raise CodecError(out.parse_errors[0].1)
  }
  match rec.array {
    Some(spec) => {
      let (sheet, text) = @value.split_key(spec.anchor)
      let host = match @value.parse_addr(text) {
        Some(a) => a
        None => raise CodecError("invalid array anchor: " + spec.anchor)
      }
      let cells : Array[Value] = []
      for dr in 0..<spec.rows {
        for dc in 0..<spec.cols {
          let a : @value.CellAddr = {
            row: host.row + dr,
            col: host.col + dc,
            abs_row: false,
            abs_col: false,
          }
          let key = @value.sheet_key(sheet, a)
          cells.push(match out.values.get(key) {
            Some(v) => v
            None => Value::Blank
          })
        }
      }
      Value::Range(@value.RangeValue::array(spec.rows, spec.cols, cells))
    }
    None =>
      match rec.anchor {
        Some(a) =>
          match out.cells.get(a) {
            Some(o) => o.value
            None => Value::Blank
          }
        None => raise CodecError("setupArrays requires anchor")
      }
  }
}

/// 跑语料对照：逐条求值并按比较策略归因（见 docs/semantics.md「数值对照策略」）。
/// `filter` 为 `Some(tag)` 时只跑带该标签的用例。纯计算，不做 IO。
pub fn run_bench(
  records : Array[CaseRecord],
  tol : Double,
  clock_tol : Double,
  filter : String?
) -> BenchReport {
  let results : Array[CaseResult] = []
  let by_source : Map[String, (Int, Int)] = Map::new()
  let by_tag : Map[String, (Int, Int)] = Map::new()
  let buckets : Map[String, Int] = Map::new()
  let mut passed = 0
  let mut total = 0
  for rec in records {
    if filter is Some(tag) {
      if !rec.tags.contains(tag) {
        continue
      }
    }
    let r = compare_case(rec, tol, clock_tol)
    results.push(r)
    total += 1
    if r.passed {
      passed += 1
    }
    bump(by_source, r.source, r.passed)
    for t in r.tags {
      bump(by_tag, t, r.passed)
    }
    let n = match buckets.get(r.bucket) {
      Some(v) => v
      None => 0
    }
    buckets[r.bucket] = n + 1
  }
  { total, passed, tol, clock_tol, results, by_source, by_tag, buckets }
}

fn counts_json(m : Map[String, (Int, Int)]) -> Json {
  let out : Map[String, Json] = Map::new()
  for key, (t, p) in m {
    out[key] = obj([
      ("total", Json::number(t.to_double())),
      ("passed", Json::number(p.to_double())),
      ("rate", Json::number(if t == 0 { 0.0 } else { p.to_double() / t.to_double() })),
    ])
  }
  Json::object(out)
}

/// 报告 → JSON（权威报告格式，即 corpus/reports/real.json）：总数/通过率/容差、
/// 按来源与标签聚合、桶计数，以及逐条失败明细。
pub fn report_to_json(rep : BenchReport) -> Json {
  let failures : Array[Json] = []
  for r in rep.results {
    if !r.passed {
      failures.push(obj([
        ("id", Json::string(r.id)),
        ("formula", Json::string(r.formula)),
        ("source", Json::string(r.source)),
        ("tags", Json::array(r.tags.map(Json::string))),
        ("bucket", Json::string(r.bucket)),
        ("expected", r.expected),
        ("actual", r.actual),
        ("detail", Json::string(r.detail)),
      ]))
    }
  }
  let bucket_map : Map[String, Json] = Map::new()
  for key, n in rep.buckets {
    bucket_map[key] = Json::number(n.to_double())
  }
  obj([
    ("total", Json::number(rep.total.to_double())),
    ("passed", Json::number(rep.passed.to_double())),
    (
      "rate",
      Json::number(
        if rep.total == 0 { 0.0 } else { rep.passed.to_double() / rep.total.to_double() },
      ),
    ),
    ("tol", Json::number(rep.tol)),
    ("clock_tol", Json::number(rep.clock_tol)),
    ("by_source", counts_json(rep.by_source)),
    ("by_tag", counts_json(rep.by_tag)),
    ("buckets", Json::object(bucket_map)),
    ("failures", Json::array(failures)),
  ])
}
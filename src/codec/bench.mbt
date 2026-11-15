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
  let evaluated = match rec.iter {
    Some(it) =>
      @facade.eval_formula_iterative(rec.formula, rec.grid, { now: rec.now }, it)
    None => @facade.eval_formula(rec.formula, rec.grid, { now: rec.now })
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
  let actual = match out.value {
    Range(r) => if r.cells.length() == 1 { r.cells[0] } else { out.value }
    v => v
  }
  let actual_json = value_to_json(actual)
  let (passed, bucket, detail) = match (rec.expected, actual) {
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
        "expected " + rec.expected.type_name() + ", got " + actual.type_name(),
      )
  }
  { ..base, passed, bucket, actual: actual_json, detail }
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
// MoonCalc × mbtexcel differential bench (W3).
//
// Standalone measurement adapter: this package NEVER imports the MoonCalc
// engine.  Each corpus record gets a fresh mbtexcel Workbook, the input grid is
// written verbatim, the candidate formula is written to ZZ1 of a private main
// sheet and evaluated with calc_cell_typed.  The typed result is then bucketed
// with the same rules as src/codec/bench.mbt (re-implemented here).
//
//   cd examples/compare
//   moon run --target native . -- --corpus ../../corpus/cases \
//       --report ../../corpus/reports/mbtexcel.json

type Json = @json.Json

///|
suberror CorpusError {
  CorpusError(String)
}

///|
suberror HarnessError {
  HarnessError(stage~ : String, msg~ : String)
}

// ---------------------------------------------------------------------------
// JSON helpers (corpus decoding + report rendering).
// ---------------------------------------------------------------------------

///|
fn obj(pairs : Array[(String, Json)]) -> Json {
  let m : Map[String, Json] = Map::new()
  for p in pairs {
    m[p.0] = p.1
  }
  Json::object(m)
}

///|
fn strip_utf8_bom(s : String) -> String {
  if s.length() > 0 && s.substring(start=0, end=1) == "\u{FEFF}" {
    s.substring(start=1, end=s.length())
  } else {
    s
  }
}

/// Display-only sanitization of lone UTF-16 surrogates, mirroring the
/// answer-key exporter (they cannot be UTF-8 encoded).
fn normalize_surrogates(s : String) -> String {
  let mut out = ""
  for c in s.iter() {
    let cp = c.to_int()
    if cp >= 0xD800 && cp <= 0xDFFF {
      out = out + "\u{FFFD}"
    } else {
      out = out + c.to_string()
    }
  }
  out
}

///|
fn ascii_upper(s : String) -> String {
  let mut out = ""
  for c in s.iter() {
    if c >= 'a' && c <= 'z' {
      out = out + Char::from_int(c.to_int() - 32).to_string()
    } else {
      out = out + c.to_string()
    }
  }
  out
}

///|
fn jfield(j : Json, name : String) -> Json raise CorpusError {
  match j {
    Object(m) =>
      match m.get(name) {
        Some(v) => v
        None => raise CorpusError("missing field: " + name)
      }
    _ => raise CorpusError("expected a JSON object for field: " + name)
  }
}

///|
fn jstr(j : Json) -> String raise CorpusError {
  match j {
    String(s) => s
    _ => raise CorpusError("expected a JSON string")
  }
}

///|
fn jnum(j : Json) -> Double raise CorpusError {
  match j {
    Number(d, ..) => d
    _ => raise CorpusError("expected a JSON number")
  }
}

///|
fn jbool(j : Json) -> Bool raise CorpusError {
  match j {
    True => true
    False => false
    _ => raise CorpusError("expected a JSON boolean")
  }
}

///|
fn jstring_array(j : Json) -> Array[String] raise CorpusError {
  match j {
    Array(a) => {
      let out : Array[String] = []
      for item in a {
        out.push(jstr(item))
      }
      out
    }
    _ => raise CorpusError("expected a JSON array of strings")
  }
}

// ---------------------------------------------------------------------------
// Corpus model.
// ---------------------------------------------------------------------------

///|
enum CellSpec {
  CNum(Double)
  CText(String)
  CBool(Bool)
  CBlank
  CFormula(String)
  CErr(String)
}

///|
enum Expected {
  ENum(Double)
  EText(String)
  EBool(Bool)
  EErr(String)
  EBlank
} derive(Debug)

///|
enum Actual {
  ANum(Double)
  AText(String)
  ABool(Bool)
  AErr(String)
  ABlank
} derive(Debug)

///|
struct IterSpec {
  max_iterations : Int
  max_change : Double
}

///|
struct Placement {
  sheet : String? // None = private main sheet
  addr : String
  spec : CellSpec
}

///|
struct Record {
  id : String
  formula : String
  grid : Array[Placement]
  names : Map[String, String]
  now : Double?
  expected : Expected
  tags : Array[String]
  source : String
  notes : String
  iter : IterSpec?
}

///|
struct CorpusFile {
  name : String
  records : Array[Record]
}

///|
fn unquote_sheet(s : String) -> String {
  if s.length() >= 2 && s[0] == '\'' && s[s.length() - 1] == '\'' {
    s.substring(start=1, end=s.length() - 1).replace_all(old="''", new="'")
  } else {
    s
  }
}

/// Split `SHEET!A1` on the LAST `!`; bare `A1` targets the private main sheet.
fn parse_grid_key(key : String) -> (String?, String) raise CorpusError {
  let mut bang = -1
  for i in 0..<key.length() {
    if key[i] == '!' {
      bang = i
    }
  }
  if bang < 0 {
    if key.length() == 0 {
      raise CorpusError("empty cell address")
    }
    (None, ascii_upper(key))
  } else {
    let raw_sheet = key.substring(start=0, end=bang)
    let addr = key.substring(start=bang + 1, end=key.length())
    let sheet = unquote_sheet(raw_sheet)
    if sheet == "" || addr == "" {
      raise CorpusError("invalid qualified cell address: " + key)
    }
    (Some(sheet), ascii_upper(addr))
  }
}

///|
fn decode_cell(j : Json) -> CellSpec raise CorpusError {
  match j {
    Null => CBlank
    True => CBool(true)
    False => CBool(false)
    String(s) => CText(s)
    Number(d, ..) => CNum(d)
    Object(m) =>
      match m.get("formula") {
        Some(fj) => CFormula(jstr(fj))
        None =>
          match m.get("error") {
            Some(ej) => CErr(jstr(ej))
            None => raise CorpusError("cell object needs formula or error")
          }
      }
    _ => raise CorpusError("unsupported grid cell encoding")
  }
}

///|
fn decode_names(j : Json) -> Map[String, String] raise CorpusError {
  let out : Map[String, String] = Map::new()
  match j {
    Object(m) => {
      for name, ref in m {
        out[ascii_upper(name)] = jstr(ref)
      }
    }
    _ => raise CorpusError("names must be a JSON object")
  }
  out
}

///|
fn decode_grid(j : Json) -> (Array[Placement], Map[String, String]) raise CorpusError {
  let placements : Array[Placement] = []
  let names : Map[String, String] = Map::new()
  match j {
    Object(m) =>
      for key, cj in m {
        if key == "names" {
          for name, ref in decode_names(cj) {
            names[name] = ref
          }
        } else {
          let (sheet, addr) = parse_grid_key(key)
          placements.push({ sheet, addr, spec: decode_cell(cj) })
        }
      }
    _ => raise CorpusError("grid must be a JSON object")
  }
  (placements, names)
}

///|
fn decode_expected(j : Json) -> Expected raise CorpusError {
  let t = jstr(jfield(j, "type"))
  match t {
    "number" => ENum(jnum(jfield(j, "value")))
    "text" => EText(jstr(jfield(j, "value")))
    "bool" => EBool(jbool(jfield(j, "value")))
    "error" => EErr(jstr(jfield(j, "value")))
    "blank" => EBlank
    _ => raise CorpusError("unknown expected value type: " + t)
  }
}

///|
fn decode_record(j : Json) -> Record raise CorpusError {
  let id = jstr(jfield(j, "id"))
  let formula = jstr(jfield(j, "formula"))
  let (grid, names) = decode_grid(jfield(j, "grid"))
  match j {
    Object(m) =>
      match m.get("names") {
        Some(nj) =>
          for name, ref in decode_names(nj) {
            names[name] = ref
          }
        None => ()
      }
    _ => raise CorpusError("record must be an object")
  }
  let now = match j {
    Object(m) =>
      match m.get("now") {
        Some(nj) => Some(jnum(nj))
        None => None
      }
    _ => None
  }
  let expected = decode_expected(jfield(j, "expected"))
  let tags = match j {
    Object(m) =>
      match m.get("tags") {
        Some(tj) => jstring_array(tj)
        None => []
      }
    _ => []
  }
  let source = match j {
    Object(m) =>
      match m.get("source") {
        Some(sj) => jstr(sj)
        None => ""
      }
    _ => ""
  }
  let notes = match j {
    Object(m) =>
      match m.get("notes") {
        Some(nj) => jstr(nj)
        None => ""
      }
    _ => ""
  }
  let iter = match j {
    Object(m) =>
      match m.get("iter") {
        Some(ij) => {
          let mi = jnum(jfield(ij, "max_iterations")).to_int()
          let mc = jnum(jfield(ij, "max_change"))
          Some({ max_iterations: mi, max_change: mc })
        }
        None => None
      }
    _ => None
  }
  { id, formula, grid, names, now, expected, tags, source, notes, iter }
}

///|
fn record_from_json(j : Json) -> Result[Record, String] {
  try Ok(decode_record(j)) catch {
    CorpusError(m) => Err(m)
  }
}

///|
fn join_path(dir : String, name : String) -> String {
  if dir.has_suffix("/") {
    dir + name
  } else {
    dir + "/" + name
  }
}

///|
fn load_corpus(dir : String) -> Array[CorpusFile] raise {
  let entries = @fs.read_dir(dir)
  let names : Array[String] = []
  for e in entries {
    if e.has_suffix(".json") {
      names.push(e)
    }
  }
  names.sort()
  let files : Array[CorpusFile] = []
  for name in names {
    let path = join_path(dir, name)
    let text = @fs.read_file_to_string(path)
    let json = @json.parse(strip_utf8_bom(text))
    let raw_records = match json {
      Object(m) => {
        match m.get("schema") {
          Some(sj) =>
            if jstr(sj) != "mooncalc-corpus/1" {
              raise CorpusError("unsupported corpus schema in " + path)
            }
          None => raise CorpusError("missing schema in " + path)
        }
        match m.get("records") {
          Some(rj) =>
            match rj {
              Array(a) => a
              _ => raise CorpusError("records must be an array in " + path)
            }
          None => raise CorpusError("missing records in " + path)
        }
      }
      _ => raise CorpusError("corpus file must be a JSON object: " + path)
    }
    let records : Array[Record] = []
    for rj in raw_records {
      match record_from_json(rj) {
        Ok(r) => records.push(r)
        Err(msg) => raise CorpusError("record decode failed in " + path + ": " + msg)
      }
    }
    files.push({ name, records })
  }
  files
}

// ---------------------------------------------------------------------------
// Evaluation through mbtexcel.
// ---------------------------------------------------------------------------

///|
struct EvalOutcome {
  actual : Actual
  eval_error : String?
}

///|
fn map_actual(v : @xlsx.CellValue?) -> Actual {
  match v {
    None => ABlank
    Some(@xlsx.CellValue::Numeric(d)) => ANum(d)
    Some(@xlsx.CellValue::String(s)) => AText(s)
    Some(@xlsx.CellValue::Bool(b)) => ABool(b)
    Some(@xlsx.CellValue::Error(e)) => AErr(e)
  }
}

/// Build a fresh workbook, write the grid, evaluate the candidate formula at
/// ZZ1 of the private main sheet, and map the typed result to four states
/// (`None` = blank).
fn run_record(rec : Record) -> EvalOutcome raise {
  let wb = @xlsx.Workbook::new()
  // Explicit sheet names are case-insensitive in Excel; collect them first so
  // the private main sheet cannot collide.
  let explicit : Map[String, Bool] = Map::new()
  let explicit_names : Array[String] = []
  for p in rec.grid {
    match p.sheet {
      Some(s) => {
        let key = ascii_upper(s)
        match explicit.get(key) {
          Some(_) => ()
          None => {
            explicit[key] = true
            explicit_names.push(s)
          }
        }
      }
      None => ()
    }
  }
  explicit_names.sort()
  let mut main_name = "MoonCalcMain"
  let mut suffix = 1
  while explicit.get(ascii_upper(main_name)) is Some(_) {
    main_name = "MoonCalcMain_" + suffix.to_string()
    suffix += 1
  }
  let main_sh = wb.new_sheet(main_name)
  for name in explicit_names {
    let _ = wb.new_sheet(name)
  }
  for name, ref in rec.names {
    wb.set_defined_name(@xlsx.DefinedName::new(name, ref))
  }
  match rec.iter {
    Some(it) =>
      wb.set_calc_props(
        Some(
          @xlsx.CalcPropsOptions::with_values(
            iterate=true,
            iterate_count=it.max_iterations.reinterpret_as_uint(),
            iterate_delta=it.max_change,
          ),
        ),
      )
    None => ()
  }
  for p in rec.grid {
    let sh = match p.sheet {
      None => main_sh
      Some(name) =>
        match wb.sheet(name) {
          Some(sh) => sh
          None => raise HarnessError(stage="setup", msg="sheet not found: " + name)
        }
    }
    match p.spec {
      CNum(d) => sh.set_cell_value(p.addr, @xlsx.CellValue::Numeric(d))
      CText(s) => sh.set_cell_value(p.addr, @xlsx.CellValue::String(s))
      CBool(b) => sh.set_cell_value(p.addr, @xlsx.CellValue::Bool(b))
      CErr(e) => sh.set_cell_value(p.addr, @xlsx.CellValue::Error(e))
      CFormula(f) => sh.set_cell_formula(p.addr, f)
      CBlank => ()
    }
  }
  main_sh.set_cell_formula("ZZ1", rec.formula)
  let value = wb.calc_cell_typed(main_name, "ZZ1")
  { actual: map_actual(value), eval_error: None }
}

///|
fn eval_record(rec : Record) -> EvalOutcome {
  try run_record(rec) catch {
    HarnessError(stage~, msg~) => {
      actual: ABlank,
      eval_error: Some(stage + ": " + msg),
    }
    e => { actual: ABlank, eval_error: Some("engine: " + @debug.to_string(e)) }
  }
}

// ---------------------------------------------------------------------------
// Bucketing (independent re-implementation of src/codec/bench.mbt).
// ---------------------------------------------------------------------------

let excel_precision_tol : Double = 1.0e-14

///|
fn rel_diff(a : Double, b : Double) -> Double {
  let aa = a.abs()
  let ab = b.abs()
  let scale = if aa > ab { aa } else { ab }
  if scale == 0.0 {
    0.0
  } else {
    (a - b).abs() / scale
  }
}

///|
fn has_tag(tags : Array[String], tag : String) -> Bool {
  for t in tags {
    if t == tag {
      return true
    }
  }
  false
}

///|
fn expected_type_name(e : Expected) -> String {
  match e {
    ENum(_) => "number"
    EText(_) => "text"
    EBool(_) => "bool"
    EErr(_) => "error"
    EBlank => "blank"
  }
}

///|
fn actual_type_name(a : Actual) -> String {
  match a {
    ANum(_) => "number"
    AText(_) => "text"
    ABool(_) => "bool"
    AErr(_) => "error"
    ABlank => "blank"
  }
}

///|
fn actual_repr(a : Actual) -> String {
  match a {
    ANum(d) => "number(" + d.to_string() + ")"
    AText(s) => "text(\"" + normalize_surrogates(s) + "\")"
    ABool(b) => "bool(" + b.to_string() + ")"
    AErr(e) => "error(" + e + ")"
    ABlank => "blank"
  }
}

///|
fn expected_to_json(e : Expected) -> Json {
  match e {
    ENum(d) => obj([("type", Json::string("number")), ("value", Json::number(d))])
    EText(s) =>
      obj([
        ("type", Json::string("text")),
        ("value", Json::string(normalize_surrogates(s))),
      ])
    EBool(b) => obj([("type", Json::string("bool")), ("value", Json::boolean(b))])
    EErr(e) => obj([("type", Json::string("error")), ("value", Json::string(e))])
    EBlank => obj([("type", Json::string("blank")), ("value", Json::null())])
  }
}

///|
fn actual_to_json(a : Actual) -> Json {
  match a {
    ANum(d) => obj([("type", Json::string("number")), ("value", Json::number(d))])
    AText(s) =>
      obj([
        ("type", Json::string("text")),
        ("value", Json::string(normalize_surrogates(s))),
      ])
    ABool(b) => obj([("type", Json::string("bool")), ("value", Json::boolean(b))])
    AErr(e) => obj([("type", Json::string("error")), ("value", Json::string(e))])
    // Blank is normalized to 0 (Excel coerces an empty referenced cell to 0).
    ABlank => obj([("type", Json::string("number")), ("value", Json::number(0.0))])
  }
}

///|
fn exact_equal(expected : Expected, actual : Actual) -> Bool {
  match (expected, actual) {
    (ENum(a), ANum(b)) => a == b
    (ENum(a), ABlank) => a == 0.0
    (EText(a), AText(b)) => a == b
    (EBool(a), ABool(b)) => a == b
    (EErr(a), AErr(b)) => a == b
    (EBlank, ABlank) => true
    (EBlank, ANum(b)) => b == 0.0
    _ => false
  }
}

///|
struct Classification {
  passed : Bool
  bucket : String
  detail : String
}

///|
fn num_classification(a : Double, b : Double, tol : Double) -> Classification {
  if a == b {
    { passed: true, bucket: "match", detail: "" }
  } else if rel_diff(a, b) <= excel_precision_tol {
    {
      passed: true,
      bucket: "excel-precision",
      detail: "within 15-significant-digit Excel representation",
    }
  } else if rel_diff(a, b) < tol {
    {
      passed: false,
      bucket: "numeric-tolerance",
      detail: "relative diff " + rel_diff(a, b).to_string(),
    }
  } else {
    { passed: false, bucket: "value-mismatch", detail: "" }
  }
}

///|
fn classify(rec : Record, actual : Actual, tol : Double, _clock_tol : Double) -> Classification {
  if has_tag(rec.tags, "clock") {
    let now_text = match rec.now {
      Some(n) => n.to_string()
      None => "none"
    }
    return {
      passed: false,
      bucket: "clock-no-injection",
      detail: "mbtexcel 0.3.2 has no clock injection (NOW/TODAY read @env.now()); " +
        "corpus now=" + now_text + " ignored; actual=" + actual_repr(actual),
    }
  }
  match (rec.expected, actual) {
    (ENum(a), ANum(b)) => num_classification(a, b, tol)
    (ENum(a), ABlank) => num_classification(a, 0.0, tol)
    (EText(a), AText(b)) =>
      if a == b {
        { passed: true, bucket: "match", detail: "" }
      } else if normalize_surrogates(a) == normalize_surrogates(b) {
        {
          passed: true,
          bucket: "surrogate-representation",
          detail: "lone surrogate serialized as U+FFFD by the VBA answer key",
        }
      } else {
        { passed: false, bucket: "value-mismatch", detail: "" }
      }
    (EBool(a), ABool(b)) =>
      if a == b {
        { passed: true, bucket: "match", detail: "" }
      } else {
        { passed: false, bucket: "value-mismatch", detail: "" }
      }
    (EErr(a), AErr(b)) =>
      if a == b {
        { passed: true, bucket: "match", detail: "" }
      } else {
        { passed: false, bucket: "value-mismatch", detail: "" }
      }
    (EBlank, ABlank) => { passed: true, bucket: "match", detail: "" }
    (EBlank, ANum(b)) =>
      if b == 0.0 {
        { passed: true, bucket: "match", detail: "" }
      } else {
        { passed: false, bucket: "type-mismatch", detail: "expected blank, got number " + b.to_string() }
      }
    _ => {
      passed: false,
      bucket: "type-mismatch",
      detail: "expected " + expected_type_name(rec.expected) + ", got " +
        actual_type_name(actual),
    }
  }
}

// ---------------------------------------------------------------------------
// Bench aggregation.
// ---------------------------------------------------------------------------

///|
struct Failure {
  id : String
  formula : String
  tags : Array[String]
  expected : Json
  actual : Json
  bucket : String
  detail : String
}

///|
struct Summary {
  total : Int
  passed : Int
  buckets : Map[String, Int]
  by_source : Map[String, (Int, Int)]
  by_tag : Map[String, (Int, Int)]
  failures : Array[Failure]
  clock_tagged : Int
  clock_exact_if_compared : Int
  iter_tagged : Int
  iter_settings : Int
}

///|
fn bump(m : Map[String, (Int, Int)], key : String, passed : Bool) -> Unit {
  let (t, p) = match m.get(key) {
    Some(v) => v
    None => (0, 0)
  }
  m[key] = (t + 1, if passed { p + 1 } else { p })
}

///|
fn bucket_names() -> Array[String] {
  [
    "match",
    "excel-precision",
    "clock-tolerance",
    "numeric-tolerance",
    "value-mismatch",
    "type-mismatch",
    "surrogate-representation",
    "parse-error",
    "clock-no-injection",
  ]
}

///|
fn run_bench(files : Array[CorpusFile], tol : Double, clock_tol : Double) -> Summary {
  let buckets : Map[String, Int] = Map::new()
  for name in bucket_names() {
    buckets[name] = 0
  }
  let by_source : Map[String, (Int, Int)] = Map::new()
  let by_tag : Map[String, (Int, Int)] = Map::new()
  let failures : Array[Failure] = []
  let mut total = 0
  let mut passed_count = 0
  let mut clock_tagged = 0
  let mut clock_exact = 0
  let mut iter_tagged = 0
  let mut iter_settings = 0
  for f in files {
    for rec in f.records {
      total += 1
      let is_clock = has_tag(rec.tags, "clock")
      if is_clock {
        clock_tagged += 1
      }
      if has_tag(rec.tags, "iter") {
        iter_tagged += 1
      }
      match rec.iter {
        Some(_) => iter_settings += 1
        None => ()
      }
      let outcome = eval_record(rec)
      let (passed, bucket, detail) = match outcome.eval_error {
        Some(msg) => (false, "parse-error", msg)
        None => {
          if is_clock && exact_equal(rec.expected, outcome.actual) {
            clock_exact += 1
          }
          let c = classify(rec, outcome.actual, tol, clock_tol)
          (c.passed, c.bucket, c.detail)
        }
      }
      let detail = match rec.iter {
        Some(_) =>
          if bucket == "match" || bucket == "excel-precision" {
            detail
          } else {
            detail +
            " | iteration settings were stored via set_calc_props but mbtexcel's evaluator is single-pass and ignores them"
          }
        None => detail
      }
      if passed {
        passed_count += 1
      }
      let n = match buckets.get(bucket) {
        Some(v) => v
        None => 0
      }
      buckets[bucket] = n + 1
      bump(by_source, rec.source, passed)
      for tag in rec.tags {
        bump(by_tag, tag, passed)
      }
      if !passed {
        let expected_json = expected_to_json(rec.expected)
        let actual_json = match outcome.eval_error {
          Some(_) => Json::null()
          None => actual_to_json(outcome.actual)
        }
        failures.push({
          id: rec.id,
          formula: rec.formula,
          tags: rec.tags,
          expected: expected_json,
          actual: actual_json,
          bucket,
          detail,
        })
      }
    }
  }
  {
    total,
    passed: passed_count,
    buckets,
    by_source,
    by_tag,
    failures,
    clock_tagged,
    clock_exact_if_compared: clock_exact,
    iter_tagged,
    iter_settings,
  }
}

// ---------------------------------------------------------------------------
// Report rendering.
// ---------------------------------------------------------------------------

///|
fn counts_json(m : Map[String, (Int, Int)]) -> Json {
  let keys : Array[String] = []
  for key, _ in m {
    keys.push(key)
  }
  keys.sort()
  let out : Map[String, Json] = Map::new()
  for key in keys {
    let (t, p) = match m.get(key) {
      Some(v) => v
      None => (0, 0)
    }
    out[key] = obj([
      ("total", Json::number(t.to_double())),
      ("passed", Json::number(p.to_double())),
      ("rate", Json::number(if t == 0 { 0.0 } else { p.to_double() / t.to_double() })),
    ])
  }
  Json::object(out)
}

///|
fn buckets_json(m : Map[String, Int]) -> Json {
  let out : Map[String, Json] = Map::new()
  for name in bucket_names() {
    let n = match m.get(name) {
      Some(v) => v
      None => 0
    }
    out[name] = Json::number(n.to_double())
  }
  Json::object(out)
}

///|
fn failures_json(failures : Array[Failure]) -> Json {
  let out : Array[Json] = []
  for f in failures {
    out.push(
      obj([
        ("id", Json::string(f.id)),
        ("formula", Json::string(f.formula)),
        ("tags", Json::array(f.tags.map(Json::string))),
        ("expected", f.expected),
        ("actual", f.actual),
        ("bucket", Json::string(f.bucket)),
        ("detail", Json::string(f.detail)),
      ]),
    )
  }
  Json::array(out)
}

///|
fn files_json(files : Array[CorpusFile]) -> Json {
  let out : Array[Json] = []
  for f in files {
    out.push(
      obj([
        ("name", Json::string(f.name)),
        ("records", Json::number(f.records.length().to_double())),
      ]),
    )
  }
  Json::array(out)
}

///|
fn report_json(
  files : Array[CorpusFile],
  summary : Summary,
  tol : Double,
  clock_tol : Double,
) -> Json {
  let failed = summary.total - summary.passed
  let rate = if summary.total == 0 {
    0.0
  } else {
    summary.passed.to_double() / summary.total.to_double()
  }
  let engine = obj([
    ("name", Json::string("mbtexcel")),
    ("version", Json::string("0.3.2")),
    ("moon", Json::string("0.1.20261104 (940aa18 2026-11-04)")),
  ])
  let corpus = obj([
    ("total", Json::number(summary.total.to_double())),
    ("files", files_json(files)),
  ])
  let tolerances = obj([
    ("tol", Json::number(tol)),
    ("clock_tol", Json::number(clock_tol)),
    ("excel_precision_tol", Json::number(excel_precision_tol)),
  ])
  let clock_attribution = obj([
    ("tagged_records", Json::number(summary.clock_tagged.to_double())),
    ("bucket", Json::string("clock-no-injection")),
    ("counted_as_passed", Json::boolean(false)),
    ("exact_matches_if_compared", Json::number(summary.clock_exact_if_compared.to_double())),
    (
      "reason",
      Json::string(
        "mbtexcel 0.3.2 has no clock injection: NOW/TODAY read the host clock via @env.now(). " +
        "The corpus `now` serial is ignored, so clock-tagged records are attributed to their own " +
        "bucket instead of being counted as matches. Recorded actual values are the live host " +
        "clock and therefore differ slightly between runs; bucket counts are stable.",
      ),
    ),
  ])
  let iter_attribution = obj([
    ("tagged_records", Json::number(summary.iter_tagged.to_double())),
    ("records_with_iter_settings", Json::number(summary.iter_settings.to_double())),
    ("bucket", Json::string("normal comparison")),
    ("status", Json::string("settings stored, evaluator single-pass")),
    (
      "reason",
      Json::string(
        "iter.max_iterations/max_change are stored with Workbook::set_calc_props, but " +
        "calc_cell_typed does not consult CalcPropsOptions: evaluation is single-pass. " +
        "Iteration cases are reported as observed, without any expectation of parity.",
      ),
    ),
  ])
  obj([
    ("engine", engine),
    ("corpus", corpus),
    ("total", Json::number(summary.total.to_double())),
    ("passed", Json::number(summary.passed.to_double())),
    ("failed", Json::number(failed.to_double())),
    ("rate", Json::number(rate)),
    ("tol", Json::number(tol)),
    ("clock_tol", Json::number(clock_tol)),
    ("tolerances", tolerances),
    ("attribution", obj([("clock", clock_attribution), ("iteration", iter_attribution)])),
    ("buckets", buckets_json(summary.buckets)),
    ("by_source", counts_json(summary.by_source)),
    ("by_tag", counts_json(summary.by_tag)),
    ("failures", failures_json(summary.failures)),
    (
      "rerun",
      Json::string(
        "cd examples/compare && moon run --target native . -- --corpus ../../corpus/cases --report ../../corpus/reports/mbtexcel.json",
      ),
    ),
  ])
}

// ---------------------------------------------------------------------------
// CLI.
// ---------------------------------------------------------------------------

///|
struct Options {
  mut corpus : String
  mut report : String
  mut tol : Double
  mut clock_tol : Double
}

///|
fn usage() -> String {
  "usage: moon run --target native . -- [--corpus <dir>] [--report <path>] [--tol <double>] [--clock-tol <double>]\n" +
  "  default corpus: ../../corpus/cases\n" +
  "  default report: ../../corpus/reports/mbtexcel.json"
}

///|
fn parse_double_arg(s : String) -> Result[Double, String] {
  try Ok(@string.parse_double(s)) catch {
    _ => Err("not a number: " + s)
  }
}

///|
fn parse_args(argv : Array[String]) -> Result[Options, String] {
  let opts : Options = {
    corpus: "../../corpus/cases",
    report: "../../corpus/reports/mbtexcel.json",
    tol: 1.0e-9,
    clock_tol: 1.0e-6,
  }
  let mut i = 1
  while i < argv.length() {
    let flag = argv[i]
    if i + 1 >= argv.length() {
      return Err("missing value for " + flag)
    }
    let val = argv[i + 1]
    match flag {
      "--corpus" => opts.corpus = val
      "--report" => opts.report = val
      "--tol" =>
        match parse_double_arg(val) {
          Ok(d) => opts.tol = d
          Err(m) => return Err(m)
        }
      "--clock-tol" =>
        match parse_double_arg(val) {
          Ok(d) => opts.clock_tol = d
          Err(m) => return Err(m)
        }
      _ => return Err("unknown flag: " + flag + "\n" + usage())
    }
    i += 2
  }
  Ok(opts)
}

///|
fn run(opts : Options) -> Unit raise {
  let files = load_corpus(opts.corpus)
  let summary = run_bench(files, opts.tol, opts.clock_tol)
  let report = report_json(files, summary, opts.tol, opts.clock_tol)
  @fs.write_string_to_file(opts.report, Json::stringify(report, indent=2) + "\n")
  let failed = summary.total - summary.passed
  println(
    "mbtexcel 0.3.2 differential bench: total=" + summary.total.to_string() +
    " passed=" + summary.passed.to_string() + " failed=" + failed.to_string(),
  )
  for name in bucket_names() {
    let n = match summary.buckets.get(name) {
      Some(v) => v
      None => 0
    }
    if n > 0 {
      println("  " + name + ": " + n.to_string())
    }
  }
  println("  clock-tagged: " + summary.clock_tagged.to_string() +
    " (exact if compared: " + summary.clock_exact_if_compared.to_string() + ")")
  println("  iter-tagged: " + summary.iter_tagged.to_string() +
    " (with settings: " + summary.iter_settings.to_string() + ")")
  println("report: " + opts.report)
}

///|
fn[T] die(msg : String) -> T {
  println("error: " + msg)
  @env.exit(1)
  panic()
}

///|
fn main {
  let opts = match parse_args(@env.args()) {
    Ok(o) => o
    Err(msg) => die(msg)
  }
  try {
    run(opts)
  } catch {
    CorpusError(msg) => die("corpus: " + msg)
    HarnessError(stage~, msg~) => die(stage + ": " + msg)
    e => die("failed: " + @debug.to_string(e))
  }
}

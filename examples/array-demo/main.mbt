// array-demo：把交集、隐式交集、CSE、多格动态数组放进一个报表工作簿，
// 用 mbtexcel 读入 → MoonCalc `recalc_arrays` 计算 → 回写缓存值 → 再读回逐格断言。
//
// 说明（诚实披露）：mbtexcel 0.3.2 能写 OOXML `t="array"`（CSE 锚点的 ref），
// 但没有动态数组 spill 元数据写入 API；因此动态数组的非锚点缓存值按普通字面值回写，
// 读回断言的是“缓存值 + 锚点公式 + CSE 元数据”，不是 Excel 运行时的 spill 元数据。
// 字面值按引擎结果类型回写（数字仍是数字、布尔仍是布尔），不再统一写成文本；
// 公式格的缓存值受 mbtexcel API 限制仍写为字符串，Excel 打开后会重算。

const WORK_DIR : String = "_build/array-demo"
const INPUT_PATH : String = WORK_DIR + "/input.xlsx"
const OUTPUT_PATH : String = WORK_DIR + "/output.xlsx"

const CSE_KEY : String = "REPORT!D4"
const CSE_RANGE : String = "D4:E5"
const CSE_FORMULA : String = "Data!A1:B2*2"
const DYN_KEY : String = "REPORT!G4"
const DYN_FORMULA : String = "Data!A1:B2+10"
const SUM_SPILL_ADDR : String = "E1"
const SUM_SPILL_FORMULA : String = "SUM(G4#)"
const SEQ_KEY : String = "REPORT!J4"
const SEQ_FORMULA : String = "SEQUENCE(3)"
const SUM_SEQ_ADDR : String = "E2"
const SUM_SEQ_FORMULA : String = "SUM(J4#)"

fn[T] die(msg : String) -> T {
  println(msg)
  panic()
}

fn ensure_work_dir() -> Unit {
  if !@fs.path_exists(WORK_DIR) {
    try @fs.create_dir(WORK_DIR) catch { _ => die("cannot create dir: " + WORK_DIR) }
  }
}

fn read_file(path : String) -> Bytes {
  try @fs.read_file_to_bytes(path) catch { _ => die("cannot read file: " + path) }
}

fn write_file(path : String, bytes : Bytes) -> Unit {
  try @fs.write_bytes_to_file(path, bytes) catch { _ => die("cannot write file: " + path) }
}

fn ascii_upper(s : String) -> String {
  let mut out = ""
  for ch in s {
    if ch >= 'a' && ch <= 'z' {
      out = out + Char::from_int(ch.to_int() - 32).to_string()
    } else {
      out = out + ch.to_string()
    }
  }
  out
}

fn number_text(d : Double) -> String {
  if !d.is_finite() {
    return "#NUM!"
  }
  if d == d.trunc() && d.abs() < 1.0e15 {
    return d.trunc().to_int().to_string()
  }
  d.to_string()
}

fn value_text(v : @value.Value) -> String {
  match v {
    @value.Value::Num(d) => number_text(d)
    @value.Value::Text(s) => s
    @value.Value::Bool(b) => if b { "TRUE" } else { "FALSE" }
    @value.Value::Err(e) => e.to_string()
    @value.Value::Blank => ""
    @value.Value::Range(r) => if r.rows * r.cols > 0 { value_text(r.cells[0]) } else { "" }
  }
}

/// 引擎值 -> 写回用的带类型字面值（数字/布尔不再退化成文本）。
fn literal_of(v : @value.Value) -> @xlsx.CellValue {
  match v {
    @value.Value::Num(d) => @xlsx.CellValue::Numeric(d)
    @value.Value::Bool(b) => @xlsx.CellValue::Bool(b)
    @value.Value::Text(s) => @xlsx.CellValue::String(s)
    @value.Value::Err(e) => @xlsx.CellValue::Error(e.to_string())
    @value.Value::Blank => @xlsx.CellValue::String("")
    @value.Value::Range(r) => if r.rows * r.cols > 0 {
      literal_of(r.cells[0])
    } else {
      @xlsx.CellValue::String("")
    }
  }
}

fn cell_value_to_engine(v : @xlsx.CellValue) -> @value.Value {
  match v {
    @xlsx.CellValue::Numeric(d) => @value.Value::Num(d)
    @xlsx.CellValue::String(s) => @value.Value::Text(s)
    @xlsx.CellValue::Bool(b) => @value.Value::Bool(b)
    @xlsx.CellValue::Error(e) => {
      let err = match @value.XlError::parse(e) {
        Some(x) => x
        None => @value.XlError::Value
      }
      @value.Value::Err(err)
    }
  }
}

fn gen_fixture() -> Unit raise @xlsx.XlsxError {
  ensure_work_dir()
  let wb = @mbtexcel.new_workbook()
  let data = wb.add_sheet("Data")
  for r in 1..=3 {
    for c in 1..=3 {
      let addr = @mbtexcel.coordinates_to_cell_name(c, r)
      let n = (r - 1) * 3 + c
      data.set_cell_value(addr, @xlsx.CellValue::Numeric(n.to_double()))
    }
  }
  let report = wb.add_sheet("Report")
  // 交集：A1:B2 ∩ B2:C3 = B2 = 5。
  report.set_cell_formula("A1", "SUM(Data!A1:B2 Data!B2:C3)")
  // 隐式交集：垂直区域按宿主行取 A2 = 4。
  report.set_cell_formula("A2", "Data!A1:A3")
  // 显式交集：@ 作用于横向区域，宿主列 A → A1 = 1。
  report.set_cell_formula("A3", "@Data!A1:C1")
  // 并集聚合：A1:A2 ∪ B1:B2 = 1+4+2+5 = 12。
  report.set_cell_formula("A4", "SUM((Data!A1:A2,Data!B1:B2))")
  // 数组字面量在普通格取左上角。
  report.set_cell_formula("A5", "={1,2;3,4}")
  // 数组广播聚合：1x2 + 2x1 → 2x2，和 = 66。
  report.set_cell_formula("B1", "SUM({1,2}+{10;20})")
  // 横向区域隐式交集：宿主列 C → C1 = 3。
  report.set_cell_formula("C3", "Data!A1:C1")
  // 二维区域在区域外宿主格：Excel 隐式交集 → #VALUE!。
  report.set_cell_formula("A7", "Data!A1:C3")
  // CSE 2x2：Data!A1:B2 * 2 = [[2,4],[8,10]]。
  report.set_cell_formula_opts(
    "D4",
    CSE_FORMULA,
    opts=@xlsx.FormulaOpts::array(CSE_RANGE),
  )
  // 动态数组：Data!A1:B2 + 10 = [[11,12],[14,15]]，溢出到 G4:H5。
  report.set_cell_formula("G4", DYN_FORMULA)
  // 普通公式聚合 spill 区域：SUM(G4:H5) = 52（宿主 E1 在区域外，`#` 是引用通道）。
  report.set_cell_formula(SUM_SPILL_ADDR, SUM_SPILL_FORMULA)
  // 第二个动态锚点：SEQUENCE(3) 溢出 J4:J6；E2 用 spill 引用聚合 = 6。
  report.set_cell_formula("J4", SEQ_FORMULA)
  report.set_cell_formula(SUM_SEQ_ADDR, SUM_SEQ_FORMULA)
  let bytes = try @mbtexcel.write(wb) catch { _ => die("mbtexcel write failed") }
  write_file(INPUT_PATH, bytes)
  println("generated fixture: " + INPUT_PATH + " (" + bytes.length().to_string() + " bytes)")
}

struct ReadFormula {
  key : String
  sheet : String
  addr : String
  formula : String
}

fn read_workbook(path : String) -> (@xlsx.Workbook, Array[ReadFormula]) raise @xlsx.XlsxError {
  let wb = @mbtexcel.read(read_file(path))
  let formulas : Array[ReadFormula] = []
  for sheet in wb.sheets() {
    let sheet_name = sheet.name()
    let prefix = ascii_upper(sheet_name)
    for r in 1..=sheet.max_row() {
      for c in 1..=sheet.max_col() {
        let addr = @mbtexcel.coordinates_to_cell_name(c, r)
        match sheet.get_cell_formula(addr) {
          Some(f) => formulas.push({ key: prefix + "!" + addr, sheet: sheet_name, addr, formula: f })
          None => ()
        }
      }
    }
  }
  (wb, formulas)
}

fn build_grid(wb : @xlsx.Workbook) -> @engine.Grid raise @xlsx.XlsxError {
  let grid = @engine.new_grid()
  for sheet in wb.sheets() {
    let prefix = ascii_upper(sheet.name())
    for r in 1..=sheet.max_row() {
      for c in 1..=sheet.max_col() {
        let addr = @mbtexcel.coordinates_to_cell_name(c, r)
        let key = prefix + "!" + addr
        match sheet.get_cell_formula(addr) {
          Some(f) => grid.cells[key] = @engine.Cell::Formula(f)
          None =>
            match sheet.get_cell_value_raw(addr) {
              Some(@xlsx.CellValue::String("")) => ()
              Some(v) => grid.cells[key] = @engine.Cell::Literal(cell_value_to_engine(v))
              None => ()
            }
        }
      }
    }
  }
  grid
}

fn writeback(
  wb : @xlsx.Workbook,
  out : @engine.ArrayRecalcOutput,
  formulas : Array[ReadFormula],
) -> Unit raise @xlsx.XlsxError {
  for item in formulas {
    if item.key == CSE_KEY || item.key == DYN_KEY || item.key == SEQ_KEY {
      continue
    }
    let sheet = match wb.sheet(item.sheet) {
      Some(s) => s
      None => die("writeback: sheet not found: " + item.sheet)
    }
    let cached = value_text(out.cells[item.key].value)
    sheet.set_cell_formula(item.addr, item.formula, value=cached)
  }
  // CSE 锚点：写 t="array" + ref；followers 用缓存值字面量补齐。
  let cse_sheet = match wb.sheet("Report") {
    Some(s) => s
    None => die("writeback: Report missing")
  }
  cse_sheet.set_cell_formula_opts(
    "D4",
    CSE_FORMULA,
    opts=@xlsx.FormulaOpts::array(CSE_RANGE),
    value=value_text(out.values[CSE_KEY]),
  )
  for dr in 0..<2 {
    for dc in 0..<2 {
      if dr == 0 && dc == 0 {
        continue
      }
      let addr = @mbtexcel.coordinates_to_cell_name(4 + dc, 4 + dr)
      let key = "REPORT!" + addr
      cse_sheet.set_cell_value(addr, literal_of(out.values[key]))
    }
  }
  // 动态数组锚点：普通公式 + 锚点缓存；followers 没有 spill 元数据，按字面值写。
  let dyn_sheet = match wb.sheet("Report") {
    Some(s) => s
    None => die("writeback: Report missing")
  }
  dyn_sheet.set_cell_formula("G4", DYN_FORMULA, value=value_text(out.values[DYN_KEY]))
  let dyn_cells : Array[(Int, Int)] = [(0, 1), (1, 0), (1, 1)]
  for (dr, dc) in dyn_cells {
    let addr = @mbtexcel.coordinates_to_cell_name(7 + dc, 4 + dr)
    let key = "REPORT!" + addr
    dyn_sheet.set_cell_value(addr, literal_of(out.values[key]))
  }
  // SEQUENCE 动态锚点：普通公式 + 锚点缓存；J5:J6 按字面值写。
  dyn_sheet.set_cell_formula("J4", SEQ_FORMULA, value=value_text(out.values[SEQ_KEY]))
  for dr in 1..<3 {
    let addr = @mbtexcel.coordinates_to_cell_name(10, 4 + dr)
    let key = "REPORT!" + addr
    dyn_sheet.set_cell_value(addr, literal_of(out.values[key]))
  }
}

fn run_demo() -> Unit raise @xlsx.XlsxError {
  if !@fs.path_exists(INPUT_PATH) {
    die("missing " + INPUT_PATH + "; run `gen` first")
  }
  let (wb, formulas) = read_workbook(INPUT_PATH)
  let grid = build_grid(wb)
  let layout = @engine.new_array_layout()
  layout.set_cse(CSE_KEY, CSE_FORMULA, 2, 2)
  layout.set_dynamic(DYN_KEY, DYN_FORMULA)
  layout.set_dynamic(SEQ_KEY, SEQ_FORMULA)
  let out = @engine.recalc_arrays(grid, layout, { now: None })
  writeback(wb, out, formulas)
  let out_bytes = try @mbtexcel.write(wb) catch { _ => die("mbtexcel write failed") }
  write_file(OUTPUT_PATH, out_bytes)

  // 读回并逐格断言。
  let wb2 = try @mbtexcel.read(out_bytes) catch { _ => die("cannot re-read output") }
  let mut checks = 0
  let mut failures = 0
  let report = match wb2.sheet("Report") {
    Some(s) => s
    None => die("re-read: Report missing")
  }
  let data = match wb2.sheet("Data") {
    Some(s) => s
    None => die("re-read: Data missing")
  }
  fn check_text(label : String, want : String, got : String) -> Unit {
    if want == got {
      checks += 1
    } else {
      failures += 1
      println("FAIL " + label + ": want `" + want + "`, got `" + got + "`")
    }
  }
  // 按引擎值类型比对读回结果（数字格必须是 Numeric，不能是文本型数字）。
  fn check_value(label : String, want : @value.Value, sheet : @xlsx.Worksheet, addr : String) -> Unit raise @xlsx.XlsxError {
    let got = match sheet.get_cell_value_raw(addr) {
      Some(v) => cell_value_to_engine(v)
      None => @value.Value::Blank
    }
    if want == got {
      checks += 1
    } else {
      failures += 1
      println("FAIL " + label + ": want `" + value_text(want) + "`, got `" + value_text(got) + "`")
    }
  }
  fn check_cached(label : String, want : String, sheet : @xlsx.Worksheet, addr : String) -> Unit raise @xlsx.XlsxError {
    match sheet.get_cell_value_raw(addr) {
      Some(@xlsx.CellValue::String(s)) => check_text(label, want, s)
      Some(other) => check_text(label, want, "typed:" + literal_snapshot(other))
      None => check_text(label, want, "<missing>")
    }
  }
  // 普通公式：公式文本 + 缓存值。
  let expected_scalar : Array[(String, String, String)] = [
    ("A1", "SUM(Data!A1:B2 Data!B2:C3)", "5"),
    ("A2", "Data!A1:A3", "4"),
    ("A3", "@Data!A1:C1", "1"),
    ("A4", "SUM((Data!A1:A2,Data!B1:B2))", "12"),
    ("A5", "={1,2;3,4}", "1"),
    ("B1", "SUM({1,2}+{10;20})", "66"),
    ("C3", "Data!A1:C1", "3"),
    ("A7", "Data!A1:C3", "#VALUE!"),
    ("E1", "SUM(G4#)", "52"),
    ("E2", "SUM(J4#)", "6"),
  ]
  for (addr, formula, want) in expected_scalar {
    let got_formula = match report.get_cell_formula(addr) {
      Some(f) => f
      None => "<missing>"
    }
    check_text("formula " + addr, formula, got_formula)
    check_cached("cached " + addr, want, report, addr)
  }
  // CSE 锚点与四个格。
  let cse_formula_got = match report.get_cell_formula("D4") {
    Some(f) => f
    None => "<missing>"
  }
  check_text("cse anchor formula", CSE_FORMULA, cse_formula_got)
  match report.get_cell_formula_info_rc(4, 4) {
    Some(info) => {
      check_text(
        "cse formula_type",
        "Array",
        match info.formula_type {
          Some(@xlsx.FormulaType::Array) => "Array"
          _ => "other"
        },
      )
      check_text(
        "cse range_ref",
        CSE_RANGE,
        match info.range_ref {
          Some(s) => s
          None => "<none>"
        },
      )
    }
    None => {
      failures += 2
      println("FAIL cse metadata: D4 has no formula info")
    }
  }
  check_cached("cse anchor cached", "2", report, "D4")
  let cse_expected : Array[(String, @value.Value)] = [
    ("E4", @value.Value::Num(4.0)),
    ("D5", @value.Value::Num(8.0)),
    ("E5", @value.Value::Num(10.0)),
  ]
  for (addr, want) in cse_expected {
    check_value("cse " + addr, want, report, addr)
  }
  // 动态数组锚点与三个 spill 格。
  let dyn_formula_got = match report.get_cell_formula("G4") {
    Some(f) => f
    None => "<missing>"
  }
  check_text("dyn anchor formula", DYN_FORMULA, dyn_formula_got)
  check_cached("dyn anchor cached", "11", report, "G4")
  let dyn_expected : Array[(String, @value.Value)] = [
    ("H4", @value.Value::Num(12.0)),
    ("G5", @value.Value::Num(14.0)),
    ("H5", @value.Value::Num(15.0)),
  ]
  for (addr, want) in dyn_expected {
    check_value("dyn " + addr, want, report, addr)
  }
  // 第二个动态锚点 SEQUENCE(3)：J4:J6 = [1;2;3]。
  let seq_formula_got = match report.get_cell_formula("J4") {
    Some(f) => f
    None => "<missing>"
  }
  check_text("sequence anchor formula", SEQ_FORMULA, seq_formula_got)
  check_cached("sequence anchor cached", "1", report, "J4")
  let seq_expected : Array[(String, @value.Value)] = [
    ("J5", @value.Value::Num(2.0)),
    ("J6", @value.Value::Num(3.0)),
  ]
  for (addr, want) in seq_expected {
    check_value("sequence " + addr, want, report, addr)
  }
  // 输入表字面量未被改动（抽查 9 格）。
  for r in 1..=3 {
    for c in 1..=3 {
      let addr = @mbtexcel.coordinates_to_cell_name(c, r)
      let want = ((r - 1) * 3 + c).to_string()
      match data.get_cell_value_raw(addr) {
        Some(@xlsx.CellValue::Numeric(d)) => check_text("data " + addr, want, number_text(d))
        Some(_) => check_text("data " + addr, want, "<non-numeric>")
        None => check_text("data " + addr, want, "<missing>")
      }
    }
  }
  let total = checks + failures
  println(
    "array-demo: formulas=" + formulas.length().to_string() +
    " checks=" + total.to_string() +
    " failures=" + failures.to_string(),
  )
  if failures > 0 {
    die("array-demo verification FAILED")
  }
  println("array-demo PASS: " + checks.to_string() + "/" + total.to_string() + " -> " + OUTPUT_PATH)
}

fn literal_snapshot(v : @xlsx.CellValue) -> String {
  match v {
    @xlsx.CellValue::Numeric(d) => "number:" + number_text(d)
    @xlsx.CellValue::String(s) => "text:" + s
    @xlsx.CellValue::Bool(b) => "bool:" + (if b { "true" } else { "false" })
    @xlsx.CellValue::Error(e) => "error:" + e
  }
}

fn main {
  let argv = @env.args()
  let cmd = if argv.length() > 1 { argv[1] } else { "" }
  match cmd {
    "gen" => try gen_fixture() catch { _ => die("gen failed") }
    "run" => try run_demo() catch { _ => die("run failed") }
    _ => die("usage: moon run examples/array-demo --target native -- <gen|run>")
  }
}

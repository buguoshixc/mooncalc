// xlsx-demo：mbtexcel 读 → MoonCalc 算 → mbtexcel 写，进程内直调（不走子进程）。
//
// 数据流：
//   1. gen 子命令用 mbtexcel 生成 fixture（不是二进制提交物，写在 _build/ 下）；
//   2. run 子命令读取首个 sheet：公式格加前导 "=" 进网格，字面量按
//      number/bool/string 映射，空白跳过；错误值单元格按 {"error": ...} 映射；
//   3. 组 {grid: ...} 请求交给 @codec.evaluate_json（与 CLI/playground 同一契约）；
//   4. 回写：公式格 set_cell_formula（公式无前导 "="，缓存值传结果文本），字面量不动；
//   5. 读回输出文件，断言公式与缓存值（以及字面量未被改动）。

type Json = @json.Json

const WORK_DIR : String = "_build/xlsx-demo"
const INPUT_PATH : String = WORK_DIR + "/input.xlsx"
const OUTPUT_PATH : String = WORK_DIR + "/output.xlsx"

fn usage() -> String {
  "usage: moon run examples/xlsx-demo --target native -- <gen|run>\n" +
  "  gen  generate " + INPUT_PATH + " with mbtexcel\n" +
  "  run  read input, evaluate with MoonCalc, write + verify " + OUTPUT_PATH
}

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

// Excel 缓存的数值文本（展示用）：整数不带小数点，其余用最短往返十进制。
fn number_text(d : Double) -> String {
  if !d.is_finite() {
    return "#NUM!"
  }
  if d == d.trunc() && d.abs() < 1.0e15 {
    return d.trunc().to_int().to_string()
  }
  d.to_string()
}

fn formula_json(formula : String) -> Json {
  let m : Map[String, Json] = Map::new()
  m["formula"] = Json::string("=" + formula)
  Json::object(m)
}

fn error_json(err : String) -> Json {
  let m : Map[String, Json] = Map::new()
  m["error"] = Json::string(err)
  Json::object(m)
}

fn json_text(v : Json) -> String {
  match v.as_string() {
    Some(s) => s
    None => ""
  }
}

fn json_number(v : Json) -> Double? {
  v.as_number()
}

fn json_bool(v : Json) -> Bool? {
  v.as_bool()
}

// engine 响应里 value:{type,value} 的缓存文本表示。
fn result_text(v : Json) -> String {
  let kind = match v.value("type") {
    Some(t) => json_text(t)
    None => ""
  }
  let value = match v.value("value") {
    Some(x) => x
    None => Json::null()
  }
  match kind {
    "number" =>
      match json_number(value) {
        Some(d) => number_text(d)
        None => ""
      }
    "text" => json_text(value)
    "bool" =>
      match json_bool(value) {
        Some(true) => "TRUE"
        Some(false) => "FALSE"
        None => ""
      }
    "error" => json_text(value)
    _ => ""
  }
}

// 字面量单元格的可比较快照（CellValue 只 derive Debug，这里归一为文本）。
fn literal_snapshot(v : @xlsx.CellValue) -> String {
  match v {
    @xlsx.CellValue::Numeric(d) => "number:" + number_text(d)
    @xlsx.CellValue::String(s) => "text:" + s
    @xlsx.CellValue::Bool(b) => "bool:" + (if b { "true" } else { "false" })
    @xlsx.CellValue::Error(e) => "error:" + e
  }
}

struct FormulaCell {
  addr : String
  formula : String
}

fn gen_demo() -> Unit raise @xlsx.XlsxError {
  ensure_work_dir()
  let wb = @mbtexcel.new_workbook()
  let sheet = wb.add_sheet("Demo")

  // 字面量：数字 / 文本 / 布尔 / 错误值。
  sheet.set_cell_value("A1", @xlsx.CellValue::Numeric(6.0))
  sheet.set_cell_value("A2", @xlsx.CellValue::Numeric(7.0))
  sheet.set_cell("C1", "MoonCalc")
  sheet.set_cell_value("F1", @xlsx.CellValue::Bool(true))
  sheet.set_cell_value("H3", @xlsx.CellValue::Error("#N/A"))
  // lookup 表（VLOOKUP 的精确命中用它）。
  sheet.set_cell("D1", "a")
  sheet.set_cell("D2", "b")
  sheet.set_cell("D3", "c")
  sheet.set_cell_value("E1", @xlsx.CellValue::Numeric(10.0))
  sheet.set_cell_value("E2", @xlsx.CellValue::Numeric(20.0))
  sheet.set_cell_value("E3", @xlsx.CellValue::Numeric(30.0))

  // 公式格：xlsx 里的公式不带前导 "="。
  sheet.set_cell_formula("A3", "SUM(A1:A2)")
  sheet.set_cell_formula("B1", "A1*A2")
  sheet.set_cell_formula("B2", "ROUND(2.675,2)")
  sheet.set_cell_formula("B3", "TEXT(1234.5,\"#,##0.00\")")
  sheet.set_cell_formula("C2", "UPPER(C1)")
  sheet.set_cell_formula("C3", "LEN(C1)")
  sheet.set_cell_formula("C4", "VLOOKUP(\"b\",D1:E3,2,FALSE)")
  sheet.set_cell_formula("F2", "NOT(F1)")
  sheet.set_cell_formula("F3", "IF(F1,1,0)")
  sheet.set_cell_formula("G1", "1/0")
  sheet.set_cell_formula("G2", "IFERROR(G1,\"fallback\")")
  sheet.set_cell_formula("H1", "DATE(2026,11,15)")
  sheet.set_cell_formula("H2", "YEAR(H1)")
  sheet.set_cell_formula("H4", "H3+1")

  let bytes = try @mbtexcel.write(wb) catch { _ => die("mbtexcel write failed") }
  write_file(INPUT_PATH, bytes)
  println("generated fixture: " + INPUT_PATH + " (" + bytes.length().to_string() + " bytes)")
}

fn run_demo() -> Unit raise @xlsx.XlsxError {
  if !@fs.path_exists(INPUT_PATH) {
    die("missing " + INPUT_PATH + "; run `gen` first")
  }
  let wb = try @mbtexcel.read(read_file(INPUT_PATH)) catch { _ => die("mbtexcel read failed: " + INPUT_PATH) }
  let sheets = wb.sheets()
  if sheets.length() == 0 {
    die("workbook has no sheets")
  }
  let sheet = sheets[0]
  let sheet_name = sheet.name()

  // 遍历首个 sheet：公式格、字面量按网格契约编码，空白跳过。
  let grid_map : Map[String, Json] = Map::new()
  let formulas : Array[FormulaCell] = []
  let literals : Array[(String, String)] = []
  let rows = sheet.max_row()
  let cols = sheet.max_col()
  for r in 1..=rows {
    for c in 1..=cols {
      let addr = try @mbtexcel.coordinates_to_cell_name(c, r) catch { _ => die("bad cell coordinate") }
      match sheet.get_cell_formula(addr) {
        Some(formula) => {
          grid_map[addr] = formula_json(formula)
          formulas.push({ addr, formula })
        }
        None =>
          match sheet.get_cell_value_raw(addr) {
            None => ()
            Some(cell) => {
              match cell {
                @xlsx.CellValue::Numeric(d) => grid_map[addr] = Json::number(d)
                @xlsx.CellValue::String(s) => grid_map[addr] = Json::string(s)
                @xlsx.CellValue::Bool(b) => grid_map[addr] = Json::boolean(b)
                @xlsx.CellValue::Error(e) => grid_map[addr] = error_json(e)
              }
              literals.push((addr, literal_snapshot(cell)))
            }
          }
      }
    }
  }

  // 进程内调用 codec：与 CLI/playground 共用同一份 JSON 网格契约。
  let request : Map[String, Json] = Map::new()
  request["grid"] = Json::object(grid_map)
  let response = @codec.evaluate_json(Json::stringify(Json::object(request)))
  let resp = try @json.parse(response) catch { _ => die("internal: invalid codec response JSON") }
  let ok = match resp.value("ok") {
    Some(v) => v.as_bool() == Some(true)
    None => false
  }
  if !ok {
    let msg = match resp.value("error") {
      Some(e) => json_text(e)
      None => "unknown error"
    }
    die("codec error: " + msg)
  }
  let values : Map[String, String] = Map::new()
  match resp.value("results") {
    Some(results) =>
      match results.as_array() {
        Some(items) =>
          for item in items {
            let target = match item.value("target") {
              Some(t) => json_text(t)
              None => ""
            }
            match item.value("value") {
              Some(v) => values[target] = result_text(v)
              None => ()
            }
          }
        None => die("codec response: results is not an array")
      }
    None => die("codec response: missing results")
  }

  // 回写：只改公式格，缓存值传引擎结果文本；字面量保持原样。
  for item in formulas {
    let cached = match values.get(item.addr) {
      Some(t) => t
      None => ""
    }
    try sheet.set_cell_formula(item.addr, item.formula, value=cached) catch {
      _ => die("set_cell_formula failed at " + item.addr)
    }
  }
  let out_bytes = try @mbtexcel.write(wb) catch { _ => die("mbtexcel write failed") }
  write_file(OUTPUT_PATH, out_bytes)

  // 读回输出文件断言缓存值与公式（以及字面量未被改动）。
  let wb2 = try @mbtexcel.read(out_bytes) catch { _ => die("cannot re-read output workbook") }
  let sheets2 = wb2.sheets()
  if sheets2.length() == 0 {
    die("output workbook has no sheets")
  }
  let sheet2 = sheets2[0]
  let mut checks = 0
  let mut failures = 0
  for item in formulas {
    let expected = match values.get(item.addr) {
      Some(t) => t
      None => ""
    }
    let got_formula = try sheet2.get_cell_formula(item.addr) catch { _ => None }
    match got_formula {
      Some(f) =>
        if f == item.formula {
          checks += 1
        } else {
          failures += 1
          println("FAIL formula " + item.addr + ": expected `" + item.formula + "`, got `" + f + "`")
        }
      None => {
        failures += 1
        println("FAIL formula " + item.addr + ": missing")
      }
    }
    let got_raw = try sheet2.get_cell_value_raw(item.addr) catch { _ => None }
    match got_raw {
      Some(cell) => {
        // set_cell_formula 把缓存值按文本类型写入，读回即 text:<缓存文本>。
        let got_text = match cell {
          @xlsx.CellValue::String(s) => s
          _ => literal_snapshot(cell)
        }
        if got_text == expected {
          checks += 1
        } else {
          failures += 1
          println("FAIL cached " + item.addr + ": expected `" + expected + "`, got `" + got_text + "`")
        }
      }
      None => {
        failures += 1
        println("FAIL cached " + item.addr + ": missing")
      }
    }
  }
  for (addr, expected) in literals {
    let got_raw = try sheet2.get_cell_value_raw(addr) catch { _ => None }
    match got_raw {
      Some(cell) => {
        let got = literal_snapshot(cell)
        if got == expected {
          checks += 1
        } else {
          failures += 1
          println("FAIL literal " + addr + ": expected `" + expected + "`, got `" + got + "`")
        }
      }
      None => {
        failures += 1
        println("FAIL literal " + addr + ": missing")
      }
    }
  }
  println(
    "xlsx-demo: sheet `" +
    sheet_name +
    "` formulas=" +
    formulas.length().to_string() +
    " literals=" +
    literals.length().to_string(),
  )
  if failures > 0 {
    die("xlsx-demo verification FAILED: " + failures.to_string() + " failure(s)")
  }
  println(
    "xlsx-demo verification PASS: " +
    checks.to_string() +
    "/" +
    checks.to_string() +
    " (formula + cached value + literal checks) -> " +
    OUTPUT_PATH,
  )
}

fn main {
  let argv = @env.args()
  let cmd = if argv.length() > 1 { argv[1] } else { "" }
  match cmd {
    "gen" =>
      try gen_demo() catch { _ => die("gen failed") }
    "run" =>
      try run_demo() catch { _ => die("run failed") }
    _ => die(usage())
  }
}

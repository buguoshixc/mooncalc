// xlsx-demo：mbtexcel 读 → MoonCalc 算 → mbtexcel 写，进程内直调（不走子进程）。
//
// 数据流（M8：多表 + 工作簿级定义名称 + 跨表/整列整行公式）：
//   1. gen 子命令用 mbtexcel 生成 3 个表的工作簿 fixture（Input / Calc / My Sheet）：
//      跨表引用、跨表区域、整列整行、带引号表名、工作簿级定义名称（Rate/Tax/Qty）；
//   2. run 子命令遍历全部 sheet：单元格键按 M8 契约归一为 `SHEET!A1`（ASCII 大写表名），
//      公式格加前导 "=" 进网格，字面量按 number/bool/string 映射，空白跳过；
//      定义名称从工作簿读出（name → refers_to）作为 grid.names 传入；
//   3. 组 {grid: {..., "names": {...}}} 请求交给 @codec.evaluate_json（与 CLI --names / playground 同一契约）；
//   4. 回写：按 `SHEET!A1` 的宿主表定位 sheet，公式格 set_cell_formula（公式无前导 "="，缓存值传结果文本），字面量不动；
//   5. 读回输出文件，逐表断言公式、缓存值与字面量，并对关键格断言已知结果（多表语义的端到端验收 L3）。

type Json = @json.Json

const WORK_DIR : String = "_build/xlsx-demo"
const INPUT_PATH : String = WORK_DIR + "/input.xlsx"
const OUTPUT_PATH : String = WORK_DIR + "/output.xlsx"

fn usage() -> String {
  "usage: moon run examples/xlsx-demo --target native -- <gen|run>\n" +
  "  gen  generate " + INPUT_PATH + " with mbtexcel (3 sheets + defined names)\n" +
  "  run  read all sheets, evaluate with MoonCalc, write + verify " + OUTPUT_PATH
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

// 与引擎 codec 的键契约一致：表名 ASCII 大写 + `!` + A1 地址。
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
  key : String // `SHEET!A1`
  sheet_name : String // 原始表名（回写定位用）
  addr : String
  formula : String
}

struct LiteralCell {
  key : String
  sheet_name : String
  addr : String
  snapshot : String
}

fn gen_demo() -> Unit raise @xlsx.XlsxError {
  ensure_work_dir()
  let wb = @mbtexcel.new_workbook()
  let input = wb.add_sheet("Input")
  let calc = wb.add_sheet("Calc")
  let quoted = wb.add_sheet("My Sheet")

  // Input：字面量（数字 / 文本 / 布尔 / 错误值）+ 查找表。
  input.set_cell("A1", "Qty")
  input.set_cell_value("A2", @xlsx.CellValue::Numeric(3.0))
  input.set_cell_value("A3", @xlsx.CellValue::Numeric(4.0))
  input.set_cell_value("A4", @xlsx.CellValue::Numeric(5.0))
  input.set_cell_value("B1", @xlsx.CellValue::Numeric(0.25)) // Rate
  input.set_cell_value("B2", @xlsx.CellValue::Numeric(0.07)) // Tax
  input.set_cell("C1", "MoonCalc")
  input.set_cell_value("D1", @xlsx.CellValue::Bool(true))
  input.set_cell("E1", "a")
  input.set_cell("E2", "b")
  input.set_cell("E3", "c")
  input.set_cell_value("F1", @xlsx.CellValue::Numeric(10.0))
  input.set_cell_value("F2", @xlsx.CellValue::Numeric(20.0))
  input.set_cell_value("F3", @xlsx.CellValue::Numeric(30.0))
  input.set_cell_value("H1", @xlsx.CellValue::Error("#N/A"))

  // My Sheet：带空格表名，跨表引用必须写成 'My Sheet'!A1。
  quoted.set_cell_value("A1", @xlsx.CellValue::Numeric(10.0))
  quoted.set_cell_value("A2", @xlsx.CellValue::Numeric(15.0))

  // Calc：跨表引用 / 跨表区域 / 定义名称 / 整列整行 / 查找 / 错误传播。
  calc.set_cell_formula("A1", "SUM(Input!A2:A4)") // 12
  calc.set_cell_formula("A2", "A1*Rate") // 3
  calc.set_cell_formula("A3", "ROUND(A2*(1+Tax),2)") // 3.21
  calc.set_cell_formula("A4", "SUM(Input!A2:A4)/COUNT(Input!A2:A4)") // 4
  calc.set_cell_formula("A5", "IF(A1>10,\"big\",\"small\")") // big
  calc.set_cell_formula("A6", "UPPER(Input!C1)") // MOONCALC
  calc.set_cell_formula("A7", "SUM('My Sheet'!A1:A2)") // 25
  calc.set_cell_formula("A8", "SUM(Input!A:A)") // 12（整列，文本表头被忽略）
  calc.set_cell_formula("A9", "SUM(Input!2:2)") // 23.07（整行：3 + 0.07 + 20，文本忽略）
  calc.set_cell_formula("A10", "COUNT(Input!A:A)") // 3
  calc.set_cell_formula("A11", "SUM(Qty)") // 12（区域形定义名称）
  calc.set_cell_formula("B1", "A3+Tax") // 3.28
  calc.set_cell_formula("B2", "VLOOKUP(\"b\",Input!E1:F3,2,FALSE)") // 20（跨表查找表）
  calc.set_cell_formula("B3", "IF(Input!D1,1,0)") // 1（跨表布尔）
  calc.set_cell_formula("B4", "Input!H1+1") // #N/A（跨表错误传播）
  calc.set_cell_formula("B5", "SUM(Input!A2:A4)+Input!F1") // 22（混合）

  // 工作簿级定义名称：refers_to 是跨表绝对引用（与 Excel 名称一致）。
  wb.set_defined_name(@xlsx.DefinedName::new("Rate", "Input!$B$1"))
  wb.set_defined_name(@xlsx.DefinedName::new("Tax", "Input!$B$2"))
  wb.set_defined_name(@xlsx.DefinedName::new("Qty", "Input!$A$2:$A$4"))

  let bytes = try @mbtexcel.write(wb) catch { _ => die("mbtexcel write failed") }
  write_file(INPUT_PATH, bytes)
  println(
    "generated fixture: " +
    INPUT_PATH +
    " (" +
    bytes.length().to_string() +
    " bytes, sheets=3, defined names=Rate/Tax/Qty)",
  )
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

  // 遍历全部 sheet：公式格、字面量按限定键编码，空白跳过。
  let grid_map : Map[String, Json] = Map::new()
  let formulas : Array[FormulaCell] = []
  let literals : Array[LiteralCell] = []
  for sheet in sheets {
    let sheet_name = sheet.name()
    let prefix = ascii_upper(sheet_name)
    let rows = sheet.max_row()
    let cols = sheet.max_col()
    for r in 1..=rows {
      for c in 1..=cols {
        let addr = try @mbtexcel.coordinates_to_cell_name(c, r) catch { _ => die("bad cell coordinate") }
        let key = prefix + "!" + addr
        match sheet.get_cell_formula(addr) {
          Some(formula) => {
            grid_map[key] = formula_json(formula)
            formulas.push({ key, sheet_name, addr, formula })
          }
          None =>
            match sheet.get_cell_value_raw(addr) {
              None => ()
              Some(cell) => {
                match cell {
                  @xlsx.CellValue::Numeric(d) => grid_map[key] = Json::number(d)
                  @xlsx.CellValue::String(s) => grid_map[key] = Json::string(s)
                  @xlsx.CellValue::Bool(b) => grid_map[key] = Json::boolean(b)
                  @xlsx.CellValue::Error(e) => grid_map[key] = error_json(e)
                }
                literals.push({ key, sheet_name, addr, snapshot: literal_snapshot(cell) })
              }
            }
        }
      }
    }
  }

  // 定义名称从工作簿读出 → grid.names（Y 名称 ASCII 大写键，值为 refers_to 文本）。
  let names_json : Map[String, Json] = Map::new()
  for dn in wb.defined_names() {
    names_json[ascii_upper(dn.name)] = Json::string(dn.refers_to)
  }
  let grid_json : Map[String, Json] = Map::new()
  for key, cell in grid_map {
    grid_json[key] = cell
  }
  if names_json.length() > 0 {
    grid_json["names"] = Json::object(names_json)
  }

  // 进程内调用 codec：与 CLI --names / playground 共用同一份 JSON 网格契约。
  let request : Map[String, Json] = Map::new()
  request["grid"] = Json::object(grid_json)
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

  // 回写：只改公式格，按宿主表定位 sheet，缓存值传引擎结果文本；字面量保持原样。
  for item in formulas {
    let target_sheet = match wb.sheet(item.sheet_name) {
      Some(sh) => sh
      None => die("writeback: sheet not found: " + item.sheet_name)
    }
    let cached = match values.get(item.key) {
      Some(t) => t
      None => ""
    }
    try target_sheet.set_cell_formula(item.addr, item.formula, value=cached) catch {
      _ => die("set_cell_formula failed at " + item.key)
    }
  }
  let out_bytes = try @mbtexcel.write(wb) catch { _ => die("mbtexcel write failed") }
  write_file(OUTPUT_PATH, out_bytes)

  // 读回输出文件：逐表断言公式文本与缓存值（以及字面量未被改动）。
  let wb2 = try @mbtexcel.read(out_bytes) catch { _ => die("cannot re-read output workbook") }
  let mut checks = 0
  let mut failures = 0
  for item in formulas {
    let sheet2 = match wb2.sheet(item.sheet_name) {
      Some(sh) => sh
      None => die("re-read: sheet not found: " + item.sheet_name)
    }
    let expected = match values.get(item.key) {
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
          println("FAIL formula " + item.key + ": expected `" + item.formula + "`, got `" + f + "`")
        }
      None => {
        failures += 1
        println("FAIL formula " + item.key + ": missing")
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
          println("FAIL cached " + item.key + ": expected `" + expected + "`, got `" + got_text + "`")
        }
      }
      None => {
        failures += 1
        println("FAIL cached " + item.key + ": missing")
      }
    }
  }
  for item in literals {
    let sheet2 = match wb2.sheet(item.sheet_name) {
      Some(sh) => sh
      None => die("re-read: sheet not found: " + item.sheet_name)
    }
    let got_raw = try sheet2.get_cell_value_raw(item.addr) catch { _ => None }
    match got_raw {
      Some(cell) => {
        let got = literal_snapshot(cell)
        if got == item.snapshot {
          checks += 1
        } else {
          failures += 1
          println("FAIL literal " + item.key + ": expected `" + item.snapshot + "`, got `" + got + "`")
        }
      }
      None => {
        failures += 1
        println("FAIL literal " + item.key + ": missing")
      }
    }
  }

  // 关键格断言已知结果：多表/名称/整列整行语义的端到端验收（L3）。
  let expected_results : Array[(String, String)] = [
    ("CALC!A1", "12"),
    ("CALC!A2", "3"),
    ("CALC!A3", "3.21"),
    ("CALC!A4", "4"),
    ("CALC!A5", "big"),
    ("CALC!A6", "MOONCALC"),
    ("CALC!A7", "25"),
    ("CALC!A8", "12"),
    ("CALC!A9", "23.07"),
    ("CALC!A10", "3"),
    ("CALC!A11", "12"),
    ("CALC!B1", "3.28"),
    ("CALC!B2", "20"),
    ("CALC!B3", "1"),
    ("CALC!B4", "#N/A"),
    ("CALC!B5", "22"),
    // 输入表的公式格为空表；断言字面量读回由 literals 循环覆盖。
  ]
  for (key, want) in expected_results {
    let got = match values.get(key) {
      Some(t) => t
      None => ""
    }
    if got == want {
      checks += 1
    } else {
      failures += 1
      println("FAIL expected " + key + ": want `" + want + "`, got `" + got + "`")
    }
  }

  println(
    "xlsx-demo: sheets=" +
    sheets.length().to_string() +
    " formulas=" +
    formulas.length().to_string() +
    " literals=" +
    literals.length().to_string() +
    " names=" +
    names_json.length().to_string(),
  )
  if failures > 0 {
    die("xlsx-demo verification FAILED: " + failures.to_string() + " failure(s)")
  }
  println(
    "xlsx-demo verification PASS: " +
    checks.to_string() +
    "/" +
    checks.to_string() +
    " (formula + cached value + literal + expected-result checks) -> " +
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

// Grid/value <-> JSON codec shared by the CLI and the wasm playground.
// Cell encoding follows corpus/schema.md (mooncalc-corpus/1).

/// JSON 编解码失败（字段缺失、类型不符、非法地址等）。
pub suberror CodecError {
  /// 携带人类可读的错误原因。
  CodecError(String)
}

/// 去掉开头的 UTF-8 BOM（U+FEFF）。Excel/VBA（ADODB.Stream）导出的 JSON 带 BOM，
/// 而 `@json.parse` 只接受裸文本。
pub fn strip_utf8_bom(s : String) -> String {
  if s.length() > 0 && s.substring(start=0, end=1) == "\u{FEFF}" {
    s.substring(start=1, end=s.length())
  } else {
    s
  }
}

fn obj(pairs : Array[(String, Json)]) -> Json {
  let m : Map[String, Json] = Map::new()
  for p in pairs {
    m[p.0] = p.1
  }
  Json::object(m)
}

fn jfield(j : Json, name : String) -> Json raise CodecError {
  match j.value(name) {
    Some(v) => v
    None => raise CodecError("missing field: " + name)
  }
}

fn jstr(j : Json) -> String raise CodecError {
  match j.as_string() {
    Some(s) => s
    None => raise CodecError("expected a JSON string")
  }
}

fn jnum(j : Json) -> Double raise CodecError {
  match j.as_number() {
    Some(d) => d
    None => raise CodecError("expected a JSON number")
  }
}

/// 值 → JSON（`{type, value}`，区域另带 `rows`/`cols`/`values`），见 corpus/schema.md。
pub fn value_to_json(v : Value) -> Json {
  match v {
    Num(d) => obj([("type", Json::string("number")), ("value", Json::number(d))])
    Text(s) => obj([("type", Json::string("text")), ("value", Json::string(s))])
    Bool(b) => obj([("type", Json::string("bool")), ("value", Json::boolean(b))])
    Err(e) =>
      obj([
        ("type", Json::string("error")),
        ("value", Json::string(e.to_string())),
      ])
    Blank => obj([("type", Json::string("blank")), ("value", Json::null())])
    Range(r) =>
      obj([
        ("type", Json::string("range")),
        ("rows", Json::number(r.rows.to_double())),
        ("cols", Json::number(r.cols.to_double())),
        ("values", Json::array(r.cells.map(value_to_json))),
      ])
  }
}

fn decode_value(j : Json) -> Value raise CodecError {
  let t = jstr(jfield(j, "type"))
  let v = jfield(j, "value")
  match t {
    "number" => Value::Num(jnum(v))
    "text" => Value::Text(jstr(v))
    "bool" =>
      match v.as_bool() {
        Some(b) => Value::Bool(b)
        None => raise CodecError("expected.value must be a bool")
      }
    "error" =>
      match @value.XlError::parse(jstr(v)) {
        Some(e) => Value::Err(e)
        None => raise CodecError("unknown error name in expected.value")
      }
    "blank" => Value::Blank
    _ => raise CodecError("unknown value type: " + t)
  }
}

/// JSON → 值（`value_to_json` 的逆操作）；不支持区域编码（语料期望值均为标量）。
pub fn value_from_json(j : Json) -> Result[Value, String] {
  try Ok(decode_value(j)) catch {
    CodecError(m) => Err(m)
  }
}

fn decode_grid(j : Json) -> Grid raise CodecError {
  let m = match j.as_object() {
    Some(m) => m
    None => raise CodecError("grid must be a JSON object")
  }
  let g = @facade.new_grid()
  for addr, cj in m {
    let a = match @facade.parse_addr(addr) {
      Some(a) => a
      None => raise CodecError("invalid cell address: " + addr)
    }
    let cell = match cj {
      Null => Cell::Literal(Value::Blank)
      True => Cell::Literal(Value::Bool(true))
      False => Cell::Literal(Value::Bool(false))
      String(s) => Cell::Literal(Value::Text(s))
      Object(_) =>
        if cj.value("formula") is Some(fj) {
          Cell::Formula(jstr(fj))
        } else if cj.value("error") is Some(ej) {
          match @value.XlError::parse(jstr(ej)) {
            Some(e) => Cell::Literal(Value::Err(e))
            None => raise CodecError("unknown error in grid cell " + addr)
          }
        } else {
          raise CodecError("grid cell object needs formula or error: " + addr)
        }
      _ =>
        match cj.as_number() {
          Some(d) => Cell::Literal(Value::Num(d))
          None => raise CodecError("unsupported grid cell encoding: " + addr)
        }
    }
    g.cells[a.key()] = cell
  }
  g
}

/// JSON 对象 → 网格。键为 A1 地址；值为字面量（数字/字符串/布尔/null=空白）
/// 或 `{formula:"=..."}` / `{error:"#DIV/0!"}`。地址会归一化为大写键。
pub fn grid_from_json(j : Json) -> Result[Grid, String] {
  try Ok(decode_grid(j)) catch {
    CodecError(m) => Err(m)
  }
}
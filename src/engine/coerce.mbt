// Single entry point for Excel coercion rules. Locale invariant: decimal
// point is '.', thousands separators / currency / date text are #VALUE!.

/// 标量化：1×1 区域取其唯一单元格，其余值原样返回。
pub fn scalarize(v : Value) -> Value {
  match v {
    Range(r) => if r.rows == 1 && r.cols == 1 { r.cells[0] } else { v }
    _ => v
  }
}

fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

fn read_int_at(chars : Array[Char], start : Int, stop : Int) -> (Int, Int) {
  let mut i = start
  let mut v = 0
  while i < stop && is_digit(chars[i]) {
    v = v * 10 + (chars[i].to_int() - 48)
    i += 1
  }
  (v, i)
}

fn digits_text(chars : Array[Char], start : Int, stop : Int) -> String {
  let mut out = ""
  for i in start..<stop {
    out = out + chars[i].to_string()
  }
  out
}

// Numeric literal: optional sign, integer digits with optional strict
// thousands grouping (first group 1-3 digits, every following group exactly
// 3), optional decimal fraction, optional exponent, optional percent sign.
fn parse_plain_number(s : String) -> Result[Double, XlError] {
  let chars = Array::from_iter(s.iter())
  let n = chars.length()
  let mut i = 0
  let mut clean = ""
  if i < n && (chars[i] == '+' || chars[i] == '-') {
    if chars[i] == '-' {
      clean = "-"
    }
    i += 1
  }
  let int_start = i
  while i < n && is_digit(chars[i]) {
    i += 1
  }
  let first_len = i - int_start
  if first_len == 0 {
    return Err(XlError::Value)
  }
  if i < n && chars[i] == ',' && first_len > 3 {
    return Err(XlError::Value)
  }
  clean = clean + digits_text(chars, int_start, i)
  while i < n && chars[i] == ',' {
    i += 1
    let gs = i
    while i < n && is_digit(chars[i]) {
      i += 1
    }
    if i - gs != 3 {
      return Err(XlError::Value)
    }
    clean = clean + digits_text(chars, gs, i)
  }
  if i < n && chars[i] == '.' {
    i += 1
    let fs = i
    while i < n && is_digit(chars[i]) {
      i += 1
    }
    if i == fs {
      return Err(XlError::Value)
    }
    clean = clean + "." + digits_text(chars, fs, i)
  }
  if i < n && (chars[i] == 'e' || chars[i] == 'E') {
    i += 1
    clean = clean + "e"
    if i < n && (chars[i] == '+' || chars[i] == '-') {
      clean = clean + chars[i].to_string()
      i += 1
    }
    let es = i
    while i < n && is_digit(chars[i]) {
      i += 1
    }
    if i == es {
      return Err(XlError::Value)
    }
    clean = clean + digits_text(chars, es, i)
  }
  let mut percent = false
  if i < n && chars[i] == '%' {
    percent = true
    i += 1
  }
  if i != n {
    return Err(XlError::Value)
  }
  let d = @string.parse_double(clean[:]) catch { _ => return Err(XlError::Value) }
  let d = @value.excel_precision(d)
  Ok(if percent { d / 100.0 } else { d })
}

fn parse_ymd_text(
  chars : Array[Char],
  start : Int,
  stop : Int
) -> Option[(Int, Int, Int)] {
  let (y, i1) = read_int_at(chars, start, stop)
  if i1 - start != 4 || i1 >= stop {
    return None
  }
  let sep = chars[i1]
  if sep != '-' && sep != '/' {
    return None
  }
  let (m, i2) = read_int_at(chars, i1 + 1, stop)
  if i2 == i1 + 1 || i2 - (i1 + 1) > 2 || i2 >= stop {
    return None
  }
  if chars[i2] != sep {
    return None
  }
  let (d, i3) = read_int_at(chars, i2 + 1, stop)
  if i3 == i2 + 1 || i3 - (i2 + 1) > 2 || i3 != stop {
    return None
  }
  if m < 1 || m > 12 || d < 0 || d > 31 {
    return None
  }
  Some((y, m, d))
}

fn parse_hms_text(chars : Array[Char], start : Int, stop : Int) -> Option[Double] {
  let (h, i1) = read_int_at(chars, start, stop)
  if i1 == start || i1 - start > 2 || i1 >= stop {
    return None
  }
  if chars[i1] != ':' {
    return None
  }
  let (m, i2) = read_int_at(chars, i1 + 1, stop)
  if i2 == i1 + 1 || i2 - (i1 + 1) > 2 {
    return None
  }
  let mut i = i2
  let mut sec = 0
  if i < stop {
    if chars[i] != ':' {
      return None
    }
    let (s, i3) = read_int_at(chars, i + 1, stop)
    if i3 == i + 1 || i3 - (i + 1) > 2 || i3 != stop {
      return None
    }
    sec = s
    i = i3
  }
  if h >= 24 || m >= 60 || sec >= 60 {
    return None
  }
  Some((h * 3600 + m * 60 + sec).to_double() / 86400.0)
}

// Locale-invariant text date accepted by Excel/zh-CN: YYYY-MM-DD or
// YYYY/M/D, optionally followed by " HH:MM[:SS]". The date must round-trip
// through the Excel serial calendar (so 1900-02-29 is accepted, 2026-02-30
// is not; US-order dates are rejected). Returns an Excel serial.
fn parse_date_text(s : String) -> Option[Double] {
  let chars = Array::from_iter(s.iter())
  let n = chars.length()
  let mut sp = -1
  for k in 0..<n {
    if chars[k] == ' ' {
      sp = k
      break
    }
  }
  let date_stop = if sp >= 0 { sp } else { n }
  let (y, m, d) = match parse_ymd_text(chars, 0, date_stop) {
    Some(v) => v
    None => return None
  }
  let mut frac = 0.0
  if sp >= 0 {
    match parse_hms_text(chars, sp + 1, n) {
      Some(f) => frac = f
      None => return None
    }
  }
  match date_serial(y, m, d) {
    Err(_) => None
    Ok(serial) => {
      let sd = serial.to_double()
      match serial_to_ymd(sd) {
        Err(_) => None
        Ok((yy, mm, dd)) =>
          if yy != y || mm != m || dd != d {
            None
          } else {
            Some(sd + frac)
          }
      }
    }
  }
}

fn parse_excel_number(text : String) -> Result[Double, XlError] {
  let s = text.trim().to_string()
  if s.length() == 0 {
    return Err(XlError::Value)
  }
  match parse_plain_number(s) {
    Ok(d) => Ok(d)
    Err(_) =>
      match parse_date_text(s) {
        Some(d) => Ok(d)
        None => Err(XlError::Value)
      }
  }
}

/// Excel 数值强制转换（算术运算、数值参数）：数字原样；空白→0；布尔→1/0；
/// 文本按 Excel 数字文法解析（含千分位/百分号/科学计数，locale 不变）；错误传播；
/// 多格区域→`#VALUE!`。
pub fn to_number(v : Value) -> Result[Double, XlError] {
  match v {
    Num(d) => Ok(d)
    Blank => Ok(0.0)
    Bool(b) => Ok(if b { 1.0 } else { 0.0 })
    Text(s) => parse_excel_number(s)
    Err(e) => Err(e)
    Range(r) =>
      if r.cells.length() == 1 {
        to_number(r.cells[0])
      } else {
        Err(XlError::Value)
      }
  }
}

/// Excel 文本强制转换（`&`、文本参数）：数字按 General 格式（15 位有效数字）；
/// 布尔→`"TRUE"`/`"FALSE"`；空白→`""`；错误传播；多格区域→`#VALUE!`。
pub fn to_text(v : Value) -> Result[String, XlError] {
  match v {
    Num(d) => if d.is_finite() { Ok(number_to_text(d)) } else { Err(XlError::Num) }
    Text(s) => Ok(s)
    Bool(b) => Ok(if b { "TRUE" } else { "FALSE" })
    Blank => Ok("")
    Err(e) => Err(e)
    Range(r) =>
      if r.cells.length() == 1 {
        to_text(r.cells[0])
      } else {
        Err(XlError::Value)
      }
  }
}

/// Excel 布尔强制转换（逻辑参数）：布尔原样；数字≠0→TRUE；空白→FALSE；
/// 文本仅接受大小写不敏感的 `"TRUE"`/`"FALSE"`，其余→`#VALUE!`；错误传播。
pub fn to_bool(v : Value) -> Result[Bool, XlError] {
  match v {
    Bool(b) => Ok(b)
    Num(d) => Ok(d != 0.0)
    Blank => Ok(false)
    Text(s) =>
      if s.compare_ignore_ascii_case("TRUE") == 0 {
        Ok(true)
      } else if s.compare_ignore_ascii_case("FALSE") == 0 {
        Ok(false)
      } else {
        Err(XlError::Value)
      }
    Err(e) => Err(e)
    Range(r) =>
      if r.cells.length() == 1 {
        to_bool(r.cells[0])
      } else {
        Err(XlError::Value)
      }
  }
}

fn blank_as(v : Value, other : Value) -> Value {
  match v {
    Blank =>
      match other {
        Num(_) => Value::Num(0.0)
        Text(_) => Value::Text("")
        Bool(_) => Value::Bool(false)
        _ => Blank
      }
    _ => v
  }
}

fn type_rank(v : Value) -> Int {
  match v {
    Num(_) | Blank => 0
    Text(_) => 1
    Bool(_) => 2
    _ => -1
  }
}

// MoonBit's String::compare is length-first; Excel text comparison is pure
// lexicographic, so compare code point by code point.
fn lex_compare(a : String, b : String) -> Int {
  let ca = Array::from_iter(a.iter())
  let cb = Array::from_iter(b.iter())
  let n = if ca.length() < cb.length() { ca.length() } else { cb.length() }
  for i in 0..<n {
    let x = ca[i].to_int()
    let y = cb[i].to_int()
    if x != y {
      return if x < y { -1 } else { 1 }
    }
  }
  if ca.length() == cb.length() {
    0
  } else if ca.length() < cb.length() {
    -1
  } else {
    1
  }
}

/// Excel 比较排序（`=` `<` 等）：**不跨类型强制转换**，类型序 number < text < boolean，
/// 文本大小写不敏感，故 `"1" = 1` 为 FALSE。返回 -1/0/1；错误值传播。
pub fn compare_values(a : Value, b : Value) -> Result[Int, XlError] {
  let a = scalarize(a)
  let b = scalarize(b)
  match a {
    Err(e) => return Err(e)
    Range(_) => return Err(XlError::Value)
    _ => ()
  }
  match b {
    Err(e) => return Err(e)
    Range(_) => return Err(XlError::Value)
    _ => ()
  }
  let a = blank_as(a, b)
  let b = blank_as(b, a)
  let ra = type_rank(a)
  let rb = type_rank(b)
  if ra != rb {
    return Ok(if ra < rb { -1 } else { 1 })
  }
  match (a, b) {
    (Num(x), Num(y)) => Ok(if x < y { -1 } else if x > y { 1 } else { 0 })
    (Text(x), Text(y)) => Ok(lex_compare(@value.unicode_lower(x), @value.unicode_lower(y)))
    (Bool(x), Bool(y)) => Ok(if x == y { 0 } else if !x { -1 } else { 1 })
    (Blank, Blank) => Ok(0)
    _ => Ok(0)
  }
}
// Single entry point for Excel coercion rules. Locale invariant: decimal
// point is '.', thousands separators / currency / date text are #VALUE!.

pub fn scalarize(v : Value) -> Value {
  match v {
    Range(r) => if r.rows == 1 && r.cols == 1 { r.cells[0] } else { v }
    _ => v
  }
}

fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

fn parse_excel_number(text : String) -> Result[Double, XlError] {
  let s = text.trim().to_string()
  let chars = Array::from_iter(s.iter())
  let n = chars.length()
  let mut i = 0
  if i < n && (chars[i] == '+' || chars[i] == '-') {
    i += 1
  }
  let mut digits = 0
  while i < n && is_digit(chars[i]) {
    i += 1
    digits += 1
  }
  if i < n && chars[i] == '.' {
    i += 1
    while i < n && is_digit(chars[i]) {
      i += 1
      digits += 1
    }
  }
  if digits == 0 {
    return Err(XlError::Value)
  }
  if i < n && (chars[i] == 'e' || chars[i] == 'E') {
    i += 1
    if i < n && (chars[i] == '+' || chars[i] == '-') {
      i += 1
    }
    let mut ed = 0
    while i < n && is_digit(chars[i]) {
      i += 1
      ed += 1
    }
    if ed == 0 {
      return Err(XlError::Value)
    }
  }
  let num_end = i
  while i < n && chars[i] == ' ' {
    i += 1
  }
  let mut percent = false
  if i < n && chars[i] == '%' {
    percent = true
    i += 1
  }
  if i != n {
    return Err(XlError::Value)
  }
  let core = s.substring(start=0, end=num_end)
  let d = @string.parse_double(core[:]) catch { _ => return Err(XlError::Value) }
  Ok(if percent { d / 100.0 } else { d })
}

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

// Comparison does NOT coerce across types: number < text < boolean,
// text case-insensitive, so "1" = 1 is FALSE.
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
    (Text(x), Text(y)) => Ok(lex_compare(@value.ascii_lower(x), @value.ascii_lower(y)))
    (Bool(x), Bool(y)) => Ok(if x == y { 0 } else if !x { -1 } else { 1 })
    (Blank, Blank) => Ok(0)
    _ => Ok(0)
  }
}
fn text_arg(v : Value) -> Result[String, XlError] {
  to_text(scalarize(v))
}

fn int_arg(vals : Array[Value], i : Int) -> Result[Int, XlError] {
  match arg_number(vals, i) {
    Ok(d) => Ok(d.trunc().to_int())
    Err(e) => Err(e)
  }
}

fn fn_left(_ctx : Ctx, args : Array[Thunk]) -> Value {
  let vals = eager(args)
  if first_error(vals) is Some(e) {
    return Value::Err(e)
  }
  let s = match text_arg(vals[0]) {
    Ok(t) => t
    Err(e) => return Value::Err(e)
  }
  let n = if vals.length() == 2 {
    match int_arg(vals, 1) {
      Ok(v) => v
      Err(e) => return Value::Err(e)
    }
  } else {
    1
  }
  if n < 0 {
    return Value::Err(XlError::Value)
  }
  // Excel LEFT/RIGHT count Unicode code points: LEFT("😀abc",1) returns the
  // whole emoji (2 UTF-16 units) while LEN counts 2 code units.
  let chars = Array::from_iter(s.iter())
  let take = if n < chars.length() { n } else { chars.length() }
  Value::Text(String::from_array(chars[:take]))
}

fn fn_right(_ctx : Ctx, args : Array[Thunk]) -> Value {
  let vals = eager(args)
  if first_error(vals) is Some(e) {
    return Value::Err(e)
  }
  let s = match text_arg(vals[0]) {
    Ok(t) => t
    Err(e) => return Value::Err(e)
  }
  let n = if vals.length() == 2 {
    match int_arg(vals, 1) {
      Ok(v) => v
      Err(e) => return Value::Err(e)
    }
  } else {
    1
  }
  if n < 0 {
    return Value::Err(XlError::Value)
  }
  let chars = Array::from_iter(s.iter())
  let take = if n < chars.length() { n } else { chars.length() }
  Value::Text(String::from_array(chars[chars.length() - take:]))
}

fn fn_mid(_ctx : Ctx, args : Array[Thunk]) -> Value {
  let vals = eager(args)
  if first_error(vals) is Some(e) {
    return Value::Err(e)
  }
  let s = match text_arg(vals[0]) {
    Ok(t) => t
    Err(e) => return Value::Err(e)
  }
  let start = match int_arg(vals, 1) {
    Ok(v) => v
    Err(e) => return Value::Err(e)
  }
  let count = match int_arg(vals, 2) {
    Ok(v) => v
    Err(e) => return Value::Err(e)
  }
  if start < 1 || count < 0 {
    return Value::Err(XlError::Value)
  }
  let len = s.length()
  let from = start - 1
  if from >= len {
    return Value::Text("")
  }
  let take = if count < len - from { count } else { len - from }
  Value::Text(s.substring(start=from, end=from + take))
}

fn fn_len(_ctx : Ctx, args : Array[Thunk]) -> Value {
  // Excel LEN counts UTF-16 code units: LEN("😀") = 2.
  match text_arg(args[0]()) {
    Err(e) => Value::Err(e)
    Ok(s) => Value::Num(s.length().to_double())
  }
}

// Excel TRIM only touches ASCII spaces: strip ends, collapse inner runs.
fn excel_trim(s : String) -> String {
  let mut out = ""
  let mut pending = false
  let mut started = false
  for c in s.iter() {
    if c == ' ' {
      if started {
        pending = true
      }
    } else {
      if pending {
        out = out + " "
        pending = false
      }
      out = out + c.to_string()
      started = true
    }
  }
  out
}

fn fn_trim(_ctx : Ctx, args : Array[Thunk]) -> Value {
  match text_arg(args[0]()) {
    Err(e) => Value::Err(e)
    Ok(s) => Value::Text(excel_trim(s))
  }
}

fn fn_upper(_ctx : Ctx, args : Array[Thunk]) -> Value {
  match text_arg(args[0]()) {
    Err(e) => Value::Err(e)
    Ok(s) => Value::Text(@value.unicode_upper(s))
  }
}

fn fn_lower(_ctx : Ctx, args : Array[Thunk]) -> Value {
  match text_arg(args[0]()) {
    Err(e) => Value::Err(e)
    Ok(s) => Value::Text(@value.unicode_lower(s))
  }
}

fn fn_concat(_ctx : Ctx, args : Array[Thunk]) -> Value {
  let vals = eager(args)
  let mut out = ""
  for v in vals {
    match v {
      Range(r) =>
        for c in r.cells {
          match to_text(c) {
            Ok(t) => out = out + t
            Err(e) => return Value::Err(e)
          }
        }
      _ =>
        match to_text(scalarize(v)) {
          Ok(t) => out = out + t
          Err(e) => return Value::Err(e)
        }
    }
  }
  Value::Text(out)
}

fn fn_value(_ctx : Ctx, args : Array[Thunk]) -> Value {
  let v = scalarize(args[0]())
  match v {
    Text(s) =>
      match parse_excel_number(s) {
        Ok(d) => Value::Num(d)
        Err(e) => Value::Err(e)
      }
    Num(d) => Value::Num(d)
    Blank => Value::Num(0.0)
    Err(e) => Value::Err(e)
    _ => Value::Err(XlError::Value)
  }
}

fn fn_find(_ctx : Ctx, args : Array[Thunk]) -> Value {
  let vals = eager(args)
  if first_error(vals) is Some(e) {
    return Value::Err(e)
  }
  let needle = match text_arg(vals[0]) {
    Ok(t) => t
    Err(e) => return Value::Err(e)
  }
  let hay = match text_arg(vals[1]) {
    Ok(t) => t
    Err(e) => return Value::Err(e)
  }
  let start = if vals.length() == 3 {
    match int_arg(vals, 2) {
      Ok(v) => v
      Err(e) => return Value::Err(e)
    }
  } else {
    1
  }
  let hc = hay.code_units()
  let nc = needle.code_units()
  let hlen = hc.length()
  let nlen = nc.length()
  if start < 1 || start > hlen + 1 {
    return Value::Err(XlError::Value)
  }
  if nlen == 0 {
    return Value::Num(start.to_double())
  }
  let mut i = start - 1
  while i + nlen <= hlen {
    let mut ok = true
    for j in 0..<nlen {
      if hc[i + j] != nc[j] {
        ok = false
        break
      }
    }
    if ok {
      return Value::Num((i + 1).to_double())
    }
    i += 1
  }
  Value::Err(XlError::Value)
}

fn fn_substitute(_ctx : Ctx, args : Array[Thunk]) -> Value {
  let vals = eager(args)
  if first_error(vals) is Some(e) {
    return Value::Err(e)
  }
  let s = match text_arg(vals[0]) {
    Ok(t) => t
    Err(e) => return Value::Err(e)
  }
  let old = match text_arg(vals[1]) {
    Ok(t) => t
    Err(e) => return Value::Err(e)
  }
  let new = match text_arg(vals[2]) {
    Ok(t) => t
    Err(e) => return Value::Err(e)
  }
  let inst = if vals.length() == 4 {
    match int_arg(vals, 3) {
      Ok(v) => v
      Err(e) => return Value::Err(e)
    }
  } else {
    0
  }
  if vals.length() == 4 && inst < 1 {
    return Value::Err(XlError::Value)
  }
  if old == "" {
    return Value::Text(s)
  }
  let sc = Array::from_iter(s.iter())
  let oc = Array::from_iter(old.iter())
  let mut out = ""
  let mut i = 0
  let mut count = 0
  while i < sc.length() {
    let mut matched = i + oc.length() <= sc.length()
    if matched {
      for j in 0..<oc.length() {
        if sc[i + j] != oc[j] {
          matched = false
          break
        }
      }
    }
    if matched {
      count += 1
      out = out + (if inst == 0 || count == inst { new } else { old })
      i += oc.length()
    } else {
      out = out + sc[i].to_string()
      i += 1
    }
  }
  Value::Text(out)
}

fn fn_text(_ctx : Ctx, args : Array[Thunk]) -> Value {
  let vals = eager(args)
  if first_error(vals) is Some(e) {
    return Value::Err(e)
  }
  let fmt = match text_arg(vals[1]) {
    Ok(t) => t
    Err(e) => return Value::Err(e)
  }
  let d = match scalarize(vals[0]) {
    Text(s) => return Value::Text(s)
    Bool(b) => return Value::Text(if b { "TRUE" } else { "FALSE" })
    Blank => 0.0
    v =>
      match to_number(v) {
        Ok(x) => x
        Err(e) => return Value::Err(e)
      }
  }
  match text_format(d, fmt) {
    Ok(s) => Value::Text(s)
    Err(e) => Value::Err(e)
  }
}
// One TEXTJOIN piece: Blank -> empty text (skipped when ignore_empty is TRUE);
// text conversion errors propagate. `None` means "do not contribute a part".
fn textjoin_piece(v : Value, ignore_empty : Bool) -> Result[String?, XlError] {
  match v {
    Blank => Ok(if ignore_empty { None } else { Some("") })
    _ =>
      match to_text(v) {
        Err(e) => Err(e)
        Ok(s) => if ignore_empty && s == "" { Ok(None) } else { Ok(Some(s)) }
      }
  }
}

// TEXTJOIN(delimiter, ignore_empty, text1, [text2], ...): joins text pieces in
// argument/row-major order; errors propagate; result > 32767 chars -> #CALC!
// (adjudicated by corpus text-textjoin-0021 against Excel 2024).
fn fn_textjoin(_ctx : Ctx, args : Array[Thunk]) -> Value {
  let delim = match text_arg(args[0]()) {
    Ok(s) => s
    Err(e) => return Value::Err(e)
  }
  let ignore_empty = match to_bool(scalarize(args[1]())) {
    Ok(b) => b
    Err(e) => return Value::Err(e)
  }
  let mut out = ""
  let mut first = true
  let mut i = 2
  while i < args.length() {
    let v = args[i]()
    match v {
      Range(r) =>
        for c in r.cells {
          match textjoin_piece(c, ignore_empty) {
            Err(e) => return Value::Err(e)
            Ok(None) => ()
            Ok(Some(s)) => {
              if !first {
                out = out + delim
              }
              out = out + s
              first = false
            }
          }
        }
      _ =>
        match textjoin_piece(scalarize(v), ignore_empty) {
          Err(e) => return Value::Err(e)
          Ok(None) => ()
          Ok(Some(s)) => {
            if !first {
              out = out + delim
            }
            out = out + s
            first = false
          }
        }
    }
    i += 1
  }
  if out.length() > 32767 {
    return Value::Err(XlError::Calc)
  }
  Value::Text(out)
}

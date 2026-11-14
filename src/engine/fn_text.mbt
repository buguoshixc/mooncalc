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
  let chars = Array::from_iter(s.iter())
  let from = start - 1
  if from >= chars.length() {
    return Value::Text("")
  }
  let take = if count < chars.length() - from { count } else { chars.length() - from }
  Value::Text(String::from_array(chars[from:from + take]))
}

fn fn_len(_ctx : Ctx, args : Array[Thunk]) -> Value {
  match text_arg(args[0]()) {
    Err(e) => Value::Err(e)
    Ok(s) => Value::Num(s.char_length().to_double())
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
    Ok(s) => Value::Text(@value.ascii_upper(s))
  }
}

fn fn_lower(_ctx : Ctx, args : Array[Thunk]) -> Value {
  match text_arg(args[0]()) {
    Err(e) => Value::Err(e)
    Ok(s) => Value::Text(@value.ascii_lower(s))
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
  let hc = Array::from_iter(hay.iter())
  let nc = Array::from_iter(needle.iter())
  if start < 1 || start > hc.length() + 1 {
    return Value::Err(XlError::Value)
  }
  if nc.length() == 0 {
    return Value::Num(start.to_double())
  }
  let mut i = start - 1
  while i + nc.length() <= hc.length() {
    let mut ok = true
    for j in 0..<nc.length() {
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
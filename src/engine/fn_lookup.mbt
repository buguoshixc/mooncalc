fn cell_eq(a : Value, b : Value) -> Bool {
  match compare_values(a, b) {
    Ok(0) => true
    _ => false
  }
}

fn vlookup_generic(vals : Array[Value], horizontal : Bool) -> Value {
  let lookup = scalarize(vals[0])
  let table = match vals[1] {
    Range(r) => r
    _ => return Value::Err(XlError::Value)
  }
  let index = match arg_number(vals, 2) {
    Ok(d) => d.trunc().to_int()
    Err(e) => return Value::Err(e)
  }
  if index < 1 {
    return Value::Err(XlError::Value)
  }
  let lines = if horizontal { table.cols } else { table.rows }
  let width = if horizontal { table.rows } else { table.cols }
  if index > width {
    return Value::Err(XlError::Ref)
  }
  let approx = if vals.length() == 4 {
    match to_bool(scalarize(vals[3])) {
      Ok(b) => b
      Err(e) => return Value::Err(e)
    }
  } else {
    true
  }
  let key_cell = (line : Int) =>
    if horizontal {
      table.cells[line]
    } else {
      table.cells[line * table.cols]
    }
  let result_cell = (line : Int) =>
    if horizontal {
      table.cells[(index - 1) * table.cols + line]
    } else {
      table.cells[line * table.cols + (index - 1)]
    }
  let mut found = -1
  if approx {
    for line in 0..<lines {
      match compare_values(key_cell(line), lookup) {
        Ok(ord) =>
          if ord <= 0 {
            found = line
          } else {
            break
          }
        Err(_) => ()
      }
    }
  } else {
    for line in 0..<lines {
      if cell_eq(key_cell(line), lookup) {
        found = line
        break
      }
    }
  }
  if found < 0 {
    return Value::Err(XlError::NA)
  }
  match result_cell(found) {
    Blank => Value::Num(0.0)
    v => v
  }
}

fn fn_vlookup(_ctx : Ctx, args : Array[Thunk]) -> Value {
  let vals = eager(args)
  if first_error(vals) is Some(e) {
    return Value::Err(e)
  }
  vlookup_generic(vals, false)
}

fn fn_hlookup(_ctx : Ctx, args : Array[Thunk]) -> Value {
  let vals = eager(args)
  if first_error(vals) is Some(e) {
    return Value::Err(e)
  }
  vlookup_generic(vals, true)
}

fn fn_index(_ctx : Ctx, args : Array[Thunk]) -> Value {
  let vals = eager(args)
  if first_error(vals) is Some(e) {
    return Value::Err(e)
  }
  let range = as_range(vals[0])
  let rn = match arg_number(vals, 1) {
    Ok(d) => d.trunc().to_int()
    Err(e) => return Value::Err(e)
  }
  let cn = if vals.length() == 3 {
    match arg_number(vals, 2) {
      Ok(d) => d.trunc().to_int()
      Err(e) => return Value::Err(e)
    }
  } else {
    1
  }
  // Single-row range with one index: linear column indexing.
  if vals.length() == 2 && range.rows == 1 && range.cols > 1 {
    if rn < 1 || rn > range.cols {
      return Value::Err(XlError::Ref)
    }
    return range.cells[rn - 1]
  }
  if rn < 0 || cn < 0 || rn > range.rows || cn > range.cols {
    return Value::Err(XlError::Ref)
  }
  if rn == 0 && cn == 0 {
    return Value::Range(range)
  }
  if rn == 0 {
    let cells : Array[Value] = []
    for r in 0..<range.rows {
      cells.push(range.cells[r * range.cols + (cn - 1)])
    }
    return Value::Range({ rows: range.rows, cols: 1, cells })
  }
  if cn == 0 {
    let cells : Array[Value] = []
    for c in 0..<range.cols {
      cells.push(range.cells[(rn - 1) * range.cols + c])
    }
    return Value::Range({ rows: 1, cols: range.cols, cells })
  }
  range.cells[(rn - 1) * range.cols + (cn - 1)]
}

fn fn_match(_ctx : Ctx, args : Array[Thunk]) -> Value {
  let vals = eager(args)
  if first_error(vals) is Some(e) {
    return Value::Err(e)
  }
  let lookup = scalarize(vals[0])
  let range = match vals[1] {
    Range(r) => r
    _ => return Value::Err(XlError::NA)
  }
  if range.rows != 1 && range.cols != 1 {
    return Value::Err(XlError::NA)
  }
  let mt = if vals.length() == 3 {
    match arg_number(vals, 2) {
      Ok(d) => d.trunc().to_int()
      Err(e) => return Value::Err(e)
    }
  } else {
    1
  }
  let cells = range.cells
  if mt == 0 {
    let pat = match lookup {
      Text(s) =>
        if s.find("*") is Some(_) || s.find("?") is Some(_) || s.find("~") is Some(_) {
          Some(s)
        } else {
          None
        }
      _ => None
    }
    for i in 0..<cells.length() {
      let hit = match pat {
        Some(p) =>
          match cells[i] {
            Text(s) => wildcard_match(p, s)
            _ => false
          }
        None => cell_eq(cells[i], lookup)
      }
      if hit {
        return Value::Num((i + 1).to_double())
      }
    }
    return Value::Err(XlError::NA)
  }
  if mt != 1 && mt != -1 {
    return Value::Err(XlError::NA)
  }
  let mut found = -1
  for i in 0..<cells.length() {
    match compare_values(cells[i], lookup) {
      Ok(ord) =>
        if (mt == 1 && ord <= 0) || (mt == -1 && ord >= 0) {
          found = i
        } else {
          break
        }
      Err(_) => ()
    }
  }
  if found < 0 {
    Value::Err(XlError::NA)
  } else {
    Value::Num((found + 1).to_double())
  }
}
// IF / IFERROR are lazy; AND / OR are eager (AND(TRUE,1/0) is #DIV/0!).

fn if_dims(v : Value) -> (Int, Int) {
  match v {
    Range(r) => (r.rows, r.cols)
    _ => (1, 1)
  }
}

fn if_cell(v : Value, row : Int, col : Int) -> Value {
  match v {
    Range(r) =>
      if r.is_union() {
        Value::Err(XlError::Value)
      } else if r.rows == 1 && r.cols == 1 {
        r.cells[0]
      } else if row < r.rows && col < r.cols {
        r.cells[row * r.cols + col]
      } else if r.rows == 1 && col < r.cols {
        r.cells[col]
      } else if r.cols == 1 && row < r.rows {
        r.cells[row]
      } else {
        Value::Err(XlError::NA)
      }
    _ => v
  }
}

fn fn_if_array(cond : Value, thenv : Value, elsev : Value) -> Value {
  let (cr, cc) = if_dims(cond)
  let (tr, tc) = if_dims(thenv)
  let (er, ec) = if_dims(elsev)
  let rows = if cr > tr { if cr > er { cr } else { er } } else if tr > er { tr } else { er }
  let cols = if cc > tc { if cc > ec { cc } else { ec } } else if tc > ec { tc } else { ec }
  let cells : Array[Value] = []
  for r in 0..<rows {
    for c in 0..<cols {
      let cv = if_cell(cond, r, c)
      let out = match cv {
        Err(e) => Value::Err(e)
        _ =>
          match to_bool(cv) {
            Err(e) => Value::Err(e)
            Ok(b) =>
              if b {
                if_cell(thenv, r, c)
              } else {
                if_cell(elsev, r, c)
              }
          }
      }
      cells.push(out)
    }
  }
  Value::Range(RangeValue::array(rows, cols, cells))
}

fn fn_if(ctx : Ctx, args : Array[Thunk]) -> Value {
  let cond = args[0]()
  let cond_is_array = match cond {
    Range(r) => r.rows > 1 || r.cols > 1
    _ => false
  }
  if cond_is_array {
    let thenv = args[1]()
    let elsev = if args.length() == 3 { args[2]() } else { Value::Bool(false) }
    return fn_if_array(cond, thenv, elsev)
  }
  match to_bool(scalarize(cond)) {
    Err(e) => Value::Err(e)
    Ok(b) =>
      if b {
        args[1]()
      } else if args.length() == 3 {
        args[2]()
      } else {
        Value::Bool(false)
      }
  }
}
// AND/OR argument channels, matching Excel:
// * references: numbers and booleans are used (numbers as <>0), text and
//   blanks are ignored, errors propagate;
// * literals: numbers/booleans used, text "TRUE"/"FALSE" parsed and any
//   other text ignored, errors propagate.
// If no logical value is found at all the result is #VALUE!.
fn and_or(args : Array[Thunk], want_all : Bool) -> Value {
  let vals = eager(args)
  let mut result = want_all
  let mut seen = false
  for v in vals {
    match v {
      Range(r) =>
        for c in r.cells {
          match c {
            Bool(b) => {
              seen = true
              result = if want_all { result && b } else { result || b }
            }
            Num(d) => {
              seen = true
              let b = d != 0.0
              result = if want_all { result && b } else { result || b }
            }
            Err(e) => return Value::Err(e)
            _ => ()
          }
        }
      _ =>
        match scalarize(v) {
          Bool(b) => {
            seen = true
            result = if want_all { result && b } else { result || b }
          }
          Num(d) => {
            seen = true
            let b = d != 0.0
            result = if want_all { result && b } else { result || b }
          }
          Text(t) =>
            if t.compare_ignore_ascii_case("TRUE") == 0 {
              seen = true
              result = if want_all { result } else { true }
            } else if t.compare_ignore_ascii_case("FALSE") == 0 {
              seen = true
              result = if want_all { false } else { result }
            }
          Err(e) => return Value::Err(e)
          _ => ()
        }
    }
  }
  if !seen {
    return Value::Err(XlError::Value)
  }
  Value::Bool(result)
}

fn fn_and(_ctx : Ctx, args : Array[Thunk]) -> Value {
  and_or(args, true)
}

fn fn_or(_ctx : Ctx, args : Array[Thunk]) -> Value {
  and_or(args, false)
}

fn fn_not(_ctx : Ctx, args : Array[Thunk]) -> Value {
  match to_bool(scalarize(args[0]())) {
    Err(e) => Value::Err(e)
    Ok(b) => Value::Bool(!b)
  }
}

fn fn_iferror(_ctx : Ctx, args : Array[Thunk]) -> Value {
  let v = scalar_output(args[0]())
  match v {
    Err(_) => args[1]()
    _ => v
  }
}
// IFS(cond1, value1, cond2, value2, ...) — lazy: conditions are evaluated in
// order and only the winning value is evaluated; no match -> #N/A; an odd
// argument count is a shape error (#VALUE!).
fn fn_ifs(_ctx : Ctx, args : Array[Thunk]) -> Value {
  if args.length() % 2 != 0 {
    return Value::Err(XlError::Value)
  }
  let mut i = 0
  while i + 1 < args.length() {
    let cond = match args[i]() {
      Err(e) => return Value::Err(e)
      v => scalarize(v)
    }
    match to_bool(cond) {
      Err(e) => return Value::Err(e)
      Ok(true) => return args[i + 1]()
      Ok(false) => ()
    }
    i += 2
  }
  Value::Err(XlError::NA)
}

// SWITCH(expr, value1, result1, [value2, result2, ...], [default]) — expr is
// evaluated once; comparison uses Excel "=" semantics (cell_eq, no wildcards);
// the matching result (or the trailing default) is evaluated lazily.
fn fn_switch(_ctx : Ctx, args : Array[Thunk]) -> Value {
  let expr = match args[0]() {
    Err(e) => return Value::Err(e)
    v => scalarize(v)
  }
  match expr {
    // Real Excel propagates an error expression / candidate immediately
    // (corpus logic-switch-0008 / 0009), it is not treated as a no-match.
    Err(e) => return Value::Err(e)
    Range(_) => return Value::Err(XlError::Value)
    _ => ()
  }
  let mut i = 1
  while i + 1 < args.length() {
    let candidate = match args[i]() {
      Err(e) => return Value::Err(e)
      v => scalarize(v)
    }
    match candidate {
      Err(e) => return Value::Err(e)
      Range(_) => return Value::Err(XlError::Value)
      _ => ()
    }
    if cell_eq(expr, candidate) {
      return args[i + 1]()
    }
    i += 2
  }
  // A trailing unpaired argument is the default value.
  if i < args.length() {
    return args[i]()
  }
  Value::Err(XlError::NA)
}

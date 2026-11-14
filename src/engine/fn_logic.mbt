// IF / IFERROR are lazy; AND / OR are eager (AND(TRUE,1/0) is #DIV/0!).

fn fn_if(_ctx : Ctx, args : Array[Thunk]) -> Value {
  match to_bool(scalarize(args[0]())) {
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
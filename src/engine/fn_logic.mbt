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

// References contribute only logical cells (numbers/text/blank ignored);
// with no logical value at all Excel yields #VALUE!. Literals coerce.
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
            Err(e) => return Value::Err(e)
            _ => ()
          }
        }
      _ =>
        match to_bool(scalarize(v)) {
          Err(e) => return Value::Err(e)
          Ok(b) => {
            seen = true
            result = if want_all { result && b } else { result || b }
          }
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
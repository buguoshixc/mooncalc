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

fn fn_and(_ctx : Ctx, args : Array[Thunk]) -> Value {
  let vals = eager(args)
  let mut result = true
  for v in vals {
    match to_bool(scalarize(v)) {
      Err(e) => return Value::Err(e)
      Ok(b) => result = result && b
    }
  }
  Value::Bool(result)
}

fn fn_or(_ctx : Ctx, args : Array[Thunk]) -> Value {
  let vals = eager(args)
  let mut result = false
  for v in vals {
    match to_bool(scalarize(v)) {
      Err(e) => return Value::Err(e)
      Ok(b) => result = result || b
    }
  }
  Value::Bool(result)
}

fn fn_not(_ctx : Ctx, args : Array[Thunk]) -> Value {
  match to_bool(scalarize(args[0]())) {
    Err(e) => Value::Err(e)
    Ok(b) => Value::Bool(!b)
  }
}

fn fn_iferror(_ctx : Ctx, args : Array[Thunk]) -> Value {
  let v = args[0]()
  match v {
    Err(_) => args[1]()
    _ => v
  }
}
fn date_arg(v : Value) -> Result[Int, XlError] {
  match to_number(scalarize(v)) {
    Err(e) => Err(e)
    Ok(d) =>
      if !d.is_finite() || d.abs() > 1.0e7 {
        Err(XlError::Num)
      } else {
        Ok(d.trunc().to_int())
      }
  }
}

fn fn_date(_ctx : Ctx, args : Array[Thunk]) -> Value {
  let vals = eager(args)
  if first_error(vals) is Some(e) {
    return Value::Err(e)
  }
  let y = match date_arg(vals[0]) {
    Ok(v) => v
    Err(e) => return Value::Err(e)
  }
  let m = match date_arg(vals[1]) {
    Ok(v) => v
    Err(e) => return Value::Err(e)
  }
  let d = match date_arg(vals[2]) {
    Ok(v) => v
    Err(e) => return Value::Err(e)
  }
  match date_serial(y, m, d) {
    Err(e) => Value::Err(e)
    Ok(s) => Value::Num(s.to_double())
  }
}

fn ymd_part(args : Array[Thunk], part : Int) -> Value {
  match to_number(scalarize(args[0]())) {
    Err(e) => Value::Err(e)
    Ok(d) =>
      match serial_to_ymd(d) {
        Err(e) => Value::Err(e)
        Ok((y, m, day)) => {
          let v = match part {
            0 => y
            1 => m
            _ => day
          }
          Value::Num(v.to_double())
        }
      }
  }
}

fn fn_year(_ctx : Ctx, args : Array[Thunk]) -> Value {
  ymd_part(args, 0)
}

fn fn_month(_ctx : Ctx, args : Array[Thunk]) -> Value {
  ymd_part(args, 1)
}

fn fn_day(_ctx : Ctx, args : Array[Thunk]) -> Value {
  ymd_part(args, 2)
}

// Clock is injected, never read: un-injected NOW/TODAY is #NUM! by contract.
fn fn_today(ctx : Ctx, _args : Array[Thunk]) -> Value {
  match ctx.now {
    Some(n) =>
      if n.is_finite() && n >= 0.0 {
        Value::Num(n.trunc())
      } else {
        Value::Err(XlError::Num)
      }
    None => Value::Err(XlError::Num)
  }
}

fn fn_now(ctx : Ctx, _args : Array[Thunk]) -> Value {
  match ctx.now {
    Some(n) => if n.is_finite() { Value::Num(n) } else { Value::Err(XlError::Num) }
    None => Value::Err(XlError::Num)
  }
}
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
// EOMONTH(start_date, months): serial of the last day of the month that is
// `months` months after start_date. Both arguments go through date_arg
// (truncation, |d| > 1e7 -> #NUM!). Month normalization and the 1900/Lotus
// calendar follow date_serial; serial 0 / phantom-day edges are adjudicated by
// the corpus (probe rows in corpus/spec/date.tsv).
fn fn_eomonth(_ctx : Ctx, args : Array[Thunk]) -> Value {
  let vals = eager(args)
  if first_error(vals) is Some(e) {
    return Value::Err(e)
  }
  let start = match date_arg(vals[0]) {
    Ok(v) => v
    Err(e) => return Value::Err(e)
  }
  let months = match date_arg(vals[1]) {
    Ok(v) => v
    Err(e) => return Value::Err(e)
  }
  let (year, month, _day) = match serial_to_ymd(start.to_double()) {
    Ok(v) => v
    Err(e) => return Value::Err(e)
  }
  // Month arithmetic on the calendar, not through DATE(y, m+months+1, 0):
  // real Excel 2024 renders EOMONTH(60,0) as 59 (February 1900 has 28 days),
  // while DATE(1900,3,0) is the phantom 60.
  let total = year * 12 + (month - 1) + months
  let ty = fdiv(total, 12)
  let tm = total - ty * 12 + 1
  if ty < 1900 || ty > 9999 {
    return Value::Err(XlError::Num)
  }
  match date_serial(ty, tm, days_in_month(ty, tm)) {
    Ok(s) => Value::Num(s.to_double())
    Err(e) => Value::Err(e)
  }
}

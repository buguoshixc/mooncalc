fn round_family(args : Array[Thunk], mode : Int) -> Value {
  let vals = eager(args)
  if first_error(vals) is Some(e) {
    return Value::Err(e)
  }
  let d = match arg_number(vals, 0) {
    Ok(x) => x
    Err(e) => return Value::Err(e)
  }
  let digits_d = match arg_number(vals, 1) {
    Ok(x) => x
    Err(e) => return Value::Err(e)
  }
  if !digits_d.is_finite() {
    return Value::Err(XlError::Num)
  }
  let mut digits = digits_d.trunc().to_int()
  if digits > 400 {
    digits = 400
  }
  if digits < -400 {
    digits = -400
  }
  Value::Num(round_excel(d, digits, mode))
}

fn fn_round(_ctx : Ctx, args : Array[Thunk]) -> Value {
  round_family(args, 0)
}

fn fn_roundup(_ctx : Ctx, args : Array[Thunk]) -> Value {
  round_family(args, 1)
}

fn fn_rounddown(_ctx : Ctx, args : Array[Thunk]) -> Value {
  round_family(args, 2)
}

fn fn_abs(_ctx : Ctx, args : Array[Thunk]) -> Value {
  match to_number(scalarize(args[0]())) {
    Err(e) => Value::Err(e)
    Ok(d) => Value::Num(d.abs())
  }
}

fn fn_int(_ctx : Ctx, args : Array[Thunk]) -> Value {
  match to_number(scalarize(args[0]())) {
    Err(e) => Value::Err(e)
    Ok(d) => {
      let f = d.floor()
      if f.is_finite() { Value::Num(f) } else { Value::Err(XlError::Num) }
    }
  }
}

fn fn_mod(_ctx : Ctx, args : Array[Thunk]) -> Value {
  let vals = eager(args)
  if first_error(vals) is Some(e) {
    return Value::Err(e)
  }
  let a = match arg_number(vals, 0) {
    Ok(x) => x
    Err(e) => return Value::Err(e)
  }
  let b = match arg_number(vals, 1) {
    Ok(x) => x
    Err(e) => return Value::Err(e)
  }
  if b == 0.0 {
    return Value::Err(XlError::Div0)
  }
  // Excel MOD: result sign follows the divisor.
  let r = a - b * (a / b).floor()
  if r.is_finite() { Value::Num(r) } else { Value::Err(XlError::Num) }
}

fn fn_power(_ctx : Ctx, args : Array[Thunk]) -> Value {
  let vals = eager(args)
  if first_error(vals) is Some(e) {
    return Value::Err(e)
  }
  let a = match arg_number(vals, 0) {
    Ok(x) => x
    Err(e) => return Value::Err(e)
  }
  let b = match arg_number(vals, 1) {
    Ok(x) => x
    Err(e) => return Value::Err(e)
  }
  pow_excel(a, b)
}

fn fn_sqrt(_ctx : Ctx, args : Array[Thunk]) -> Value {
  match to_number(scalarize(args[0]())) {
    Err(e) => Value::Err(e)
    Ok(d) =>
      if d < 0.0 {
        Value::Err(XlError::Num)
      } else {
        Value::Num(d.sqrt())
      }
  }
}

fn fn_sum(_ctx : Ctx, args : Array[Thunk]) -> Value {
  let vals = eager(args)
  match collect_numbers(vals, false) {
    Err(e) => Value::Err(e)
    Ok(nums) => {
      let mut total = 0.0
      for d in nums {
        total += d
      }
      Value::Num(total)
    }
  }
}

fn fn_sumif(_ctx : Ctx, args : Array[Thunk]) -> Value {
  let vals = eager(args)
  // Range errors never match; criteria errors propagate; sum-range errors
  // propagate per matched cell below.
  match scalarize(vals[1]) {
    Err(e) => return Value::Err(e)
    _ => ()
  }
  let range = as_range(vals[0])
  let crit = parse_criteria(vals[1])
  let sum_range = if vals.length() == 3 { Some(as_range(vals[2])) } else { None }
  let mut total = 0.0
  for i in 0..<range.cells.length() {
    if criteria_match(range.cells[i], crit) {
      let sv = match sum_range {
        None => range.cells[i]
        Some(sr) => if i < sr.cells.length() { sr.cells[i] } else { Value::Blank }
      }
      match sv {
        Num(d) => total += d
        Err(e) => return Value::Err(e)
        _ => ()
      }
    }
  }
  Value::Num(total)
}

fn fn_sumproduct(_ctx : Ctx, args : Array[Thunk]) -> Value {
  let vals = eager(args)
  if first_error(vals) is Some(e) {
    return Value::Err(e)
  }
  let ranges : Array[RangeValue] = []
  for v in vals {
    match v {
      Range(r) => ranges.push(r)
      _ => return Value::Err(XlError::Value)
    }
  }
  let rows = ranges[0].rows
  let cols = ranges[0].cols
  for r in ranges {
    if r.rows != rows || r.cols != cols {
      return Value::Err(XlError::Value)
    }
  }
  let mut total = 0.0
  for i in 0..<(rows * cols) {
    let mut prod = 1.0
    for r in ranges {
      match r.cells[i] {
        Num(d) => prod *= d
        Err(e) => return Value::Err(e)
        _ => prod = 0.0
      }
    }
    total += prod
  }
  Value::Num(total)
}
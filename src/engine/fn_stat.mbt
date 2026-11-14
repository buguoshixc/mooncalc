fn fn_average(_ctx : Ctx, args : Array[Thunk]) -> Value {
  let vals = eager(args)
  match collect_numbers(vals, true) {
    Err(e) => Value::Err(e)
    Ok(nums) => {
      if nums.length() == 0 {
        return Value::Err(XlError::Div0)
      }
      let mut total = 0.0
      for d in nums {
        total += d
      }
      Value::Num(total / nums.length().to_double())
    }
  }
}

fn fn_count(_ctx : Ctx, args : Array[Thunk]) -> Value {
  // Excel COUNT ignores error arguments (COUNT(#N/A) = 0); only numbers in
  // references or coercible numeric literals are counted.
  let vals = eager(args)
  Value::Num(count_channel(vals, 0).to_double())
}

fn fn_counta(_ctx : Ctx, args : Array[Thunk]) -> Value {
  // COUNTA counts error arguments as non-empty (COUNTA(#N/A) = 1).
  let vals = eager(args)
  Value::Num(count_channel(vals, 1).to_double())
}

fn fn_countif(_ctx : Ctx, args : Array[Thunk]) -> Value {
  let vals = eager(args)
  // Range errors never match and do not propagate; criteria errors do.
  match scalarize(vals[1]) {
    Err(e) => return Value::Err(e)
    _ => ()
  }
  let range = as_range(vals[0])
  let crit = parse_criteria(vals[1])
  let mut n = 0
  for c in range.cells {
    if criteria_match(c, crit) {
      n += 1
    }
  }
  Value::Num(n.to_double())
}

fn min_max(args : Array[Thunk], want_min : Bool) -> Value {
  let vals = eager(args)
  match collect_numbers(vals, true) {
    Err(e) => Value::Err(e)
    Ok(nums) => {
      if nums.length() == 0 {
        return Value::Num(0.0)
      }
      let mut best = nums[0]
      for d in nums {
        if want_min {
          if d < best {
            best = d
          }
        } else if d > best {
          best = d
        }
      }
      Value::Num(best)
    }
  }
}

fn fn_min(_ctx : Ctx, args : Array[Thunk]) -> Value {
  min_max(args, true)
}

fn fn_max(_ctx : Ctx, args : Array[Thunk]) -> Value {
  min_max(args, false)
}

fn fn_median(_ctx : Ctx, args : Array[Thunk]) -> Value {
  let vals = eager(args)
  match collect_numbers(vals, true) {
    Err(e) => Value::Err(e)
    Ok(nums) => {
      if nums.length() == 0 {
        return Value::Err(XlError::Num)
      }
      nums.sort()
      let n = nums.length()
      let mid = n / 2
      if n % 2 == 1 {
        Value::Num(nums[mid])
      } else {
        Value::Num((nums[mid - 1] + nums[mid]) / 2.0)
      }
    }
  }
}
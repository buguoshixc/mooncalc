// Batch 4 (ADR 0007): STDEV/VAR/PERCENTILE, REPLACE/SEARCH/PROPER,
// CEILING/FLOOR, CHOOSE, XOR. Provisional semantics (source: manual,
// legacy Excel docs); the real-Excel corpus is the authoritative judge.

fn stdev_var(args : Array[Thunk], want_sqrt : Bool) -> Value {
  let vals = eager(args)
  match collect_numbers(vals, true) {
    Err(e) => Value::Err(e)
    Ok(nums) => {
      let n = nums.length()
      if n < 2 {
        return Value::Err(XlError::Div0)
      }
      let mut mean = 0.0
      for d in nums {
        mean += d
      }
      mean = mean / n.to_double()
      let mut ss = 0.0
      for d in nums {
        let dev = d - mean
        ss = ss + dev * dev
      }
      let variance = ss / (n - 1).to_double()
      Value::Num(if want_sqrt { variance.sqrt() } else { variance })
    }
  }
}

fn fn_stdev(_ctx : Ctx, args : Array[Thunk]) -> Value {
  stdev_var(args, true)
}

fn fn_var(_ctx : Ctx, args : Array[Thunk]) -> Value {
  stdev_var(args, false)
}

fn fn_percentile(_ctx : Ctx, args : Array[Thunk]) -> Value {
  let vals = eager(args)
  if first_error(vals) is Some(e) {
    return Value::Err(e)
  }
  let range = as_range(vals[0])
  let nums : Array[Double] = []
  for c in range.cells {
    match c {
      Num(d) => nums.push(d)
      Err(e) => return Value::Err(e)
      _ => ()
    }
  }
  let k = match arg_number(vals, 1) {
    Ok(d) => d
    Err(e) => return Value::Err(e)
  }
  if nums.length() == 0 {
    return Value::Err(XlError::Num)
  }
  if !k.is_finite() || k < 0.0 || k > 1.0 {
    return Value::Err(XlError::Num)
  }
  nums.sort()
  let n = nums.length()
  if n == 1 {
    return Value::Num(nums[0])
  }
  let rank = k * (n - 1).to_double()
  let f = rank.floor().to_int()
  if f >= n - 1 {
    return Value::Num(nums[n - 1])
  }
  let frac = rank - f.to_double()
  Value::Num(nums[f] + frac * (nums[f + 1] - nums[f]))
}

// REPLACE counts UTF-16 code units (like MID/LEN); a split surrogate pair is
// preserved as-is at this stage, corpus adjudicates Excel's exact behaviour.
fn fn_replace(_ctx : Ctx, args : Array[Thunk]) -> Value {
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
  let new = match text_arg(vals[3]) {
    Ok(t) => t
    Err(e) => return Value::Err(e)
  }
  if start < 1 || count < 0 {
    return Value::Err(XlError::Value)
  }
  let len = s.length()
  let from = start - 1
  if from >= len {
    return Value::Text(s + new)
  }
  let take = if count < len - from { count } else { len - from }
  Value::Text(
    s.substring(start=0, end=from) + new +
    s.substring(start=from + take, end=len),
  )
}

// Substring glob for SEARCH: pattern exhausted = hit (unlike the anchored
// wildcard_match used by criteria). ~ escapes, * any run, ? one code unit.
fn search_glob_at(
  kinds : Array[Int],
  lits : Array[UInt16],
  hc : ArrayView[UInt16],
  from : Int
) -> Bool {
  let mut ti = from
  let mut pi = 0
  let mut li = 0
  let mut star = -1
  let mut star_li = 0
  let mut mark = 0
  while pi < kinds.length() {
    let kind = kinds[pi]
    if kind == 2 {
      star = pi
      star_li = li
      mark = ti
      pi += 1
      continue
    }
    let matched = if kind == 1 {
      ti < hc.length()
    } else {
      ti < hc.length() && hc[ti] == lits[li]
    }
    if matched {
      if kind == 0 {
        li += 1
      }
      pi += 1
      ti += 1
      continue
    }
    if star >= 0 {
      pi = star + 1
      li = star_li
      mark += 1
      ti = mark
      continue
    }
    return false
  }
  true
}

fn fn_search(_ctx : Ctx, args : Array[Thunk]) -> Value {
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
  let hc = @value.ascii_lower(hay).code_units()
  let nc = @value.ascii_lower(needle).code_units()
  let hlen = hc.length()
  if start < 1 || start > hlen + 1 {
    return Value::Err(XlError::Value)
  }
  if nc.length() == 0 {
    return Value::Num(start.to_double())
  }
  let kinds : Array[Int] = []
  let lits : Array[UInt16] = []
  let mut i = 0
  while i < nc.length() {
    let c = nc[i]
    if c == (126 : UInt16) && i + 1 < nc.length() {
      kinds.push(0)
      lits.push(nc[i + 1])
      i += 2
    } else if c == (42 : UInt16) {
      kinds.push(2)
      i += 1
    } else if c == (63 : UInt16) {
      kinds.push(1)
      i += 1
    } else {
      kinds.push(0)
      lits.push(c)
      i += 1
    }
  }
  let mut pos = start - 1
  while pos <= hlen {
    if search_glob_at(kinds, lits, hc, pos) {
      return Value::Num((pos + 1).to_double())
    }
    pos += 1
  }
  Value::Err(XlError::Value)
}

// PROPER: capitalize the first letter of each word, lowercase the rest; word
// boundary = any character without case distinction (ASCII + BMP simple
// mappings via the shared case tables; full/title mappings adjudicated later).
fn fn_proper(_ctx : Ctx, args : Array[Thunk]) -> Value {
  match text_arg(args[0]()) {
    Err(e) => Value::Err(e)
    Ok(s) => {
      let mut out = ""
      let mut word_start = true
      for c in s.iter() {
        let cs = c.to_string()
        let up = @value.unicode_upper(cs)
        let lo = @value.unicode_lower(cs)
        if up != lo {
          out = out + (if word_start { up } else { lo })
          word_start = false
        } else {
          out = out + cs
          word_start = true
        }
      }
      Value::Text(out)
    }
  }
}

// 15-significant-digit half-up normalization (same as round_excel's first
// step): removes binary float tails before quotient ceil/floor.
fn normalize15(d : Double) -> Double {
  if d == 0.0 {
    return 0.0
  }
  dec_to_double(round_dec(dec_of_double(d), 15, 0))
}

// Legacy CEILING/FLOOR: round to a multiple of significance; ceil/floor of the
// 15-digit-normalized quotient reproduces all sign combinations (away from
// zero when both negative, toward zero for negative number / positive
// significance). number>0 with sig<0 is #NUM!; sig=0 yields 0.
fn ceiling_floor(args : Array[Thunk], up : Bool) -> Value {
  let vals = eager(args)
  if first_error(vals) is Some(e) {
    return Value::Err(e)
  }
  let d = match arg_number(vals, 0) {
    Ok(x) => x
    Err(e) => return Value::Err(e)
  }
  let sig = match arg_number(vals, 1) {
    Ok(x) => x
    Err(e) => return Value::Err(e)
  }
  if !d.is_finite() || !sig.is_finite() {
    return Value::Err(XlError::Num)
  }
  if sig == 0.0 {
    return Value::Num(0.0)
  }
  if d > 0.0 && sig < 0.0 {
    return Value::Err(XlError::Num)
  }
  let q = normalize15(d / sig)
  let r = if up { q.ceil() } else { q.floor() }
  let result = normalize15(r * sig)
  if result.is_finite() { Value::Num(result) } else { Value::Err(XlError::Num) }
}

fn fn_ceiling(_ctx : Ctx, args : Array[Thunk]) -> Value {
  ceiling_floor(args, true)
}

fn fn_floor(_ctx : Ctx, args : Array[Thunk]) -> Value {
  ceiling_floor(args, false)
}

// CHOOSE: 1-based truncated index, lazy — only the selected value is evaluated.
fn fn_choose(_ctx : Ctx, args : Array[Thunk]) -> Value {
  let idx = match to_number(scalarize(args[0]())) {
    Err(e) => return Value::Err(e)
    Ok(d) => d.trunc().to_int()
  }
  if idx < 1 || idx > args.length() - 1 {
    return Value::Err(XlError::Value)
  }
  args[idx]()
}

// XOR: parity of TRUE count; same eager channels as AND/OR (errors propagate,
// references use numbers/booleans, literals parse "TRUE"/"FALSE").
fn fn_xor(_ctx : Ctx, args : Array[Thunk]) -> Value {
  let vals = eager(args)
  let mut count = 0
  let mut seen = false
  for v in vals {
    match v {
      Range(r) =>
        for c in r.cells {
          match c {
            Bool(b) => {
              seen = true
              if b {
                count += 1
              }
            }
            Num(d) => {
              seen = true
              if d != 0.0 {
                count += 1
              }
            }
            Err(e) => return Value::Err(e)
            _ => ()
          }
        }
      _ =>
        match scalarize(v) {
          Bool(b) => {
            seen = true
            if b {
              count += 1
            }
          }
          Num(d) => {
            seen = true
            if d != 0.0 {
              count += 1
            }
          }
          Text(t) =>
            if t.compare_ignore_ascii_case("TRUE") == 0 {
              seen = true
              count += 1
            } else if t.compare_ignore_ascii_case("FALSE") == 0 {
              seen = true
            }
          Err(e) => return Value::Err(e)
          _ => ()
        }
    }
  }
  if !seen {
    return Value::Err(XlError::Value)
  }
  Value::Bool(count % 2 == 1)
}
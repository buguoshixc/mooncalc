// XLOOKUP subset: vector lookup_array / return_array (row or column), match
// modes 0 (exact), -1 (exact or next smaller), 1 (exact or next larger),
// 2 (wildcard, text only); search modes 1 (first-to-last), -1 (last-to-first),
// 2 (binary ascending) and -2 (binary descending).
//
// Binary search is a standard lower_bound over the vector in the declared sort
// direction. It assumes the data really is sorted; unsorted data may return a
// not-found fallback (adjudicated by corpus lookup-xlookup-0027..0030). Binary
// search and wildcard matching are not combined (#VALUE!). Duplicate keys are
// not specified by Excel's documentation; our descending path returns the
// duplicate nearest the small end of the descending order, which is what the
// 2024 probe showed.

fn xlookup_vector(v : Value) -> Result[Array[Value], XlError] {
  match v {
    Range(r) =>
      if r.rows == 1 || r.cols == 1 {
        Ok(r.cells)
      } else {
        Err(XlError::Value)
      }
    Err(e) => Err(e)
    _ => Err(XlError::Value)
  }
}

fn xlookup_mode_arg(args : Array[Thunk], i : Int, fallback : Int) -> Result[Int, XlError] {
  if i >= args.length() {
    return Ok(fallback)
  }
  match args[i]() {
    Err(e) => Err(e)
    v =>
      match to_number(scalarize(v)) {
        Err(e) => Err(e)
        Ok(d) =>
          // Real Excel rejects a non-integral match_mode/search_mode with
          // #VALUE! (corpus lookup-xlookup-0036: match_mode -1.9).
          if !d.is_finite() || d.abs() > 1000.0 || d != d.trunc() {
            Err(XlError::Value)
          } else {
            Ok(d.to_int())
          }
      }
  }
}

fn xlookup_exact(
  cells : Array[Value],
  lookup : Value,
  forward : Bool,
  wildcard : Bool
) -> Int {
  let n = cells.length()
  let pattern = match lookup {
    Text(s) => Some(s)
    _ => None
  }
  let mut k = 0
  while k < n {
    let idx = if forward { k } else { n - 1 - k }
    let hit = if wildcard {
      match (pattern, cells[idx]) {
        (Some(p), Text(s)) => wildcard_match(p, s)
        (None, cell) => cell_eq(cell, lookup)
        _ => false
      }
    } else {
      match cells[idx] {
        // Error cells inside the lookup vector can be compared: unknown is
        // "no match" for exact search rather than a hard failure.
        Err(_) => false
        cell => cell_eq(cell, lookup)
      }
    }
    if hit {
      return idx
    }
    k += 1
  }
  -1
}

// Approximate modes scan linearly and pick the closest comparable candidate:
// mode -1 keeps the largest value <= lookup, mode 1 the smallest >= lookup.
// An exact hit wins immediately in the requested search direction.
fn xlookup_approx(
  cells : Array[Value],
  lookup : Value,
  want_smaller : Bool,
  forward : Bool
) -> Int {
  let n = cells.length()
  let exact = xlookup_exact(cells, lookup, forward, false)
  if exact >= 0 {
    return exact
  }
  let mut best = -1
  let mut k = 0
  while k < n {
    let idx = if forward { k } else { n - 1 - k }
    match cells[idx] {
      Err(_) => ()
      cell =>
        match compare_values(cell, lookup) {
          Err(_) => ()
          Ok(ord) => {
            let candidate = if want_smaller { ord < 0 } else { ord > 0 }
            if candidate {
              let better = if best < 0 {
                true
              } else {
                match compare_values(cell, cells[best]) {
                  Ok(cmp) => if want_smaller { cmp > 0 } else { cmp < 0 }
                  Err(_) => false
                }
              }
              if better {
                best = idx
              }
            }
          }
        }
    }
    k += 1
  }
  best
}

// Binary search over a vector assumed sorted in the declared direction.
// `ascending` reinterprets the array as its reverse, which keeps the
// lower_bound logic identical for both directions and reproduces the duplicate
// position observed in the 2024 probe (descending duplicate keys resolve to
// the last appearance in the original array).
fn xlookup_binary(
  cells : Array[Value],
  lookup : Value,
  match_mode : Int,
  ascending : Bool
) -> Result[Int, XlError] {
  let n = cells.length()
  if n == 0 {
    return Ok(-1)
  }
  let at = (i : Int) => if ascending { cells[i] } else { cells[n - 1 - i] }
  let mut lo = 0
  let mut hi = n
  while lo < hi {
    let mid = (lo + hi) / 2
    let ord = match compare_values(at(mid), lookup) {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    if ord < 0 {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  let pos = lo
  let exact = if pos < n {
    match compare_values(at(pos), lookup) {
      Ok(0) => true
      _ => false
    }
  } else {
    false
  }
  let view_idx = if match_mode == 0 {
    if exact {
      pos
    } else {
      return Ok(-1)
    }
  } else if match_mode == -1 {
    if exact {
      pos
    } else if pos > 0 {
      pos - 1
    } else {
      return Ok(-1)
    }
  } else if exact {
    pos
  } else if pos < n {
    pos
  } else {
    return Ok(-1)
  }
  Ok(if ascending { view_idx } else { n - 1 - view_idx })
}

fn fn_xlookup(_ctx : Ctx, args : Array[Thunk]) -> Value {
  // 1. lookup_value (scalar; >1-cell range has no implicit intersection here).
  let lookup = match args[0]() {
    Err(e) => return Value::Err(e)
    v =>
      match scalarize(v) {
        Err(e) => return Value::Err(e)
        s => s
      }
  }
  if lookup is Range(_) {
    return Value::Err(XlError::Value)
  }
  // 2. lookup_array and 3. return_array: same-shape vectors.
  let lookup_cells = match xlookup_vector(args[1]()) {
    Ok(a) => a
    Err(e) => return Value::Err(e)
  }
  let return_cells = match xlookup_vector(args[2]()) {
    Ok(a) => a
    Err(e) => return Value::Err(e)
  }
  if lookup_cells.length() != return_cells.length() {
    return Value::Err(XlError::Value)
  }
  // 5. match_mode / 6. search_mode are eager numeric arguments.
  let match_mode = match xlookup_mode_arg(args, 4, 0) {
    Ok(m) => m
    Err(e) => return Value::Err(e)
  }
  let search_mode = match xlookup_mode_arg(args, 5, 1) {
    Ok(s) => s
    Err(e) => return Value::Err(e)
  }
  if match_mode != 0 && match_mode != -1 && match_mode != 1 && match_mode != 2 {
    return Value::Err(XlError::Value)
  }
  let (forward, binary) = match search_mode {
    1 => (true, None)
    -1 => (false, None)
    2 => (true, Some(true))
    -2 => (false, Some(false))
    _ => return Value::Err(XlError::Value)
  }
  let found = match binary {
    Some(ascending) => {
      if match_mode == 2 {
        // Wildcard matching cannot be combined with binary search.
        return Value::Err(XlError::Value)
      }
      match xlookup_binary(lookup_cells, lookup, match_mode, ascending) {
        Ok(i) => i
        Err(e) => return Value::Err(e)
      }
    }
    None => {
      if match_mode == 0 {
        xlookup_exact(lookup_cells, lookup, forward, false)
      } else if match_mode == 2 {
        xlookup_exact(lookup_cells, lookup, forward, true)
      } else if match_mode == -1 {
        xlookup_approx(lookup_cells, lookup, true, forward)
      } else {
        xlookup_approx(lookup_cells, lookup, false, forward)
      }
    }
  }
  if found < 0 {
    // 4. if_not_found is only evaluated on a miss.
    return if args.length() >= 4 { args[3]() } else { Value::Err(XlError::NA) }
  }
  match return_cells[found] {
    Blank => Value::Num(0.0)
    v => v
  }
}

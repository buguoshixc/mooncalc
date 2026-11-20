fn eager(thunks : Array[Thunk]) -> Array[Value] {
  let vals : Array[Value] = []
  for t in thunks {
    vals.push(t())
  }
  vals
}

/// 聚合/条件函数不接受并集引用（Excel 对这些函数返回 #VALUE!）。
fn reject_union(v : Value) -> Bool {
  match v {
    Range(r) => r.is_union()
    _ => false
  }
}

fn first_error(vals : Array[Value]) -> XlError? {
  for v in vals {
    match scalarize(v) {
      Err(e) => return Some(e)
      _ => ()
    }
  }
  None
}

// Output boundary: unwrap 1x1 refs, >1-cell ranges are #VALUE! (no spill).
// Excel formulas never return a true blank: a blank result displays as 0
// (ISBLANK on a formula cell is always FALSE).
fn scalar_output(v : Value) -> Value {
  match scalarize(v) {
    // A multi-cell result at the top level behaves like the top-left cell of
    // a spilled array (the macro reads only ZZ1): single-column ranges (e.g.
    // INDEX(range,0,n)) yield their first row; row/2-D ranges are #VALUE!
    // because implicit intersection at the formula's column is out of range.
    Range(r) =>
      if r.cols == 1 {
        r.cells[0]
      } else {
        Value::Err(XlError::Value)
      }
    Blank => Value::Num(0.0)
    s => s
  }
}

// Literal/computed error arguments propagate; reference errors stay in the
// range channel (refs arrive wrapped as 1x1 ranges, never as bare Err).
fn direct_error(vals : Array[Value]) -> XlError? {
  for v in vals {
    match v {
      Err(e) => return Some(e)
      _ => ()
    }
  }
  None
}

fn arg_number(vals : Array[Value], i : Int) -> Result[Double, XlError] {
  to_number(scalarize(vals[i]))
}

fn as_range(v : Value) -> RangeValue {
  match v {
    Range(r) => r
    _ => RangeValue::array(1, 1, [v])
  }
}

// Aggregate channel: range cells contribute only numbers (text/bool/blank
// ignored, errors propagate); direct scalar args coerce via to_number.
// skip_blank: AVERAGE/MEDIAN ignore a direct blank reference, SUM counts it 0.
fn collect_numbers(
  vals : Array[Value],
  skip_blank : Bool
) -> Result[Array[Double], XlError] {
  let out : Array[Double] = []
  for v in vals {
    match v {
      Range(r) =>
        for c in r.cells {
          match c {
            Num(d) => out.push(d)
            Err(e) => return Err(e)
            _ => ()
          }
        }
      Blank => if !skip_blank { out.push(0.0) }
      _ =>
        match to_number(scalarize(v)) {
          Ok(d) => out.push(d)
          Err(e) => return Err(e)
        }
    }
  }
  Ok(out)
}

// mode 0 = COUNT (numbers only), mode 1 = COUNTA (anything non-blank).
fn count_channel(vals : Array[Value], mode : Int) -> Int {
  let mut n = 0
  for v in vals {
    match v {
      Range(r) =>
        for c in r.cells {
          if mode == 0 {
            match c {
              Num(_) => n += 1
              _ => ()
            }
          } else {
            match c {
              Blank => ()
              _ => n += 1
            }
          }
        }
      _ => {
        let sv = scalarize(v)
        if mode == 0 {
          match sv {
            Blank | Err(_) => ()
            _ =>
              match to_number(sv) {
                Ok(_) => n += 1
                Err(_) => ()
              }
          }
        } else {
          match sv {
            Blank => ()
            _ => n += 1
          }
        }
      }
    }
  }
  n
}
fn eager(thunks : Array[Thunk]) -> Array[Value] {
  let vals : Array[Value] = []
  for t in thunks {
    vals.push(t())
  }
  vals
}

fn first_error(vals : Array[Value]) -> XlError? {
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
    _ => { rows: 1, cols: 1, cells: [v] }
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
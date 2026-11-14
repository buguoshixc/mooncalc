struct Criteria {
  op : String
  operand : Value
}

fn parse_criteria(v : Value) -> Criteria {
  let sv = scalarize(v)
  match sv {
    Text(s) => {
      let ops = [">=", "<=", "<>", ">", "<", "="]
      for op in ops {
        if s.has_prefix(op) {
          let rest = s.substring(start=op.length())
          let operand = match parse_excel_number(rest) {
            Ok(d) => Value::Num(d)
            Err(_) => Value::Text(rest)
          }
          return { op, operand }
        }
      }
      match parse_excel_number(s) {
        Ok(d) => { op: "=", operand: Value::Num(d) }
        Err(_) => { op: "=", operand: sv }
      }
    }
    _ => { op: "=", operand: sv }
  }
}

enum CritToken {
  Lit(Char)
  Any
  Star
}

// Excel glob: * any run, ? one char, ~ escapes the next char.
// Case-insensitive.
fn wildcard_match(pattern : String, text : String) -> Bool {
  let pc = Array::from_iter(@value.ascii_lower(pattern).iter())
  let toks : Array[CritToken] = []
  let mut i = 0
  while i < pc.length() {
    let c = pc[i]
    if c == '~' && i + 1 < pc.length() {
      toks.push(Lit(pc[i + 1]))
      i += 2
    } else if c == '*' {
      toks.push(Star)
      i += 1
    } else if c == '?' {
      toks.push(Any)
      i += 1
    } else {
      toks.push(Lit(c))
      i += 1
    }
  }
  let tc = Array::from_iter(@value.ascii_lower(text).iter())
  let mut ti = 0
  let mut pi = 0
  let mut star = -1
  let mut mark = 0
  while ti < tc.length() {
    if pi < toks.length() {
      match toks[pi] {
        Lit(c) =>
          if c == tc[ti] {
            pi += 1
            ti += 1
            continue
          }
        Any => {
          pi += 1
          ti += 1
          continue
        }
        Star => {
          star = pi
          mark = ti
          pi += 1
          continue
        }
      }
    }
    if star >= 0 {
      pi = star + 1
      mark += 1
      ti = mark
      continue
    }
    return false
  }
  while pi < toks.length() {
    match toks[pi] {
      Star => pi += 1
      _ => return false
    }
  }
  true
}

fn criteria_match(cell : Value, crit : Criteria) -> Bool {
  let cell = scalarize(cell)
  match crit.operand {
    Num(target) => {
      let cn = match cell {
        Num(d) => Some(d)
        Text(s) =>
          match parse_excel_number(s) {
            Ok(d) => Some(d)
            Err(_) => None
          }
        _ => None
      }
      match cn {
        None => false
        Some(d) =>
          match crit.op {
            "=" => d == target
            "<>" => d != target
            ">" => d > target
            "<" => d < target
            ">=" => d >= target
            "<=" => d <= target
            _ => false
          }
      }
    }
    Text(t) =>
      match cell {
        Text(s) => {
          let lt = @value.ascii_lower(s)
          let lp = @value.ascii_lower(t)
          match crit.op {
            "=" => wildcard_match(t, s)
            "<>" => !wildcard_match(t, s)
            ">" => lex_compare(lt, lp) > 0
            "<" => lex_compare(lt, lp) < 0
            ">=" => lex_compare(lt, lp) >= 0
            "<=" => lex_compare(lt, lp) <= 0
            _ => false
          }
        }
        _ => false
      }
    Bool(b) =>
      match cell {
        Bool(c) => if crit.op == "<>" { b != c } else { b == c }
        _ => false
      }
    _ => false
  }
}
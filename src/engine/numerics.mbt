// Excel arithmetic is decimal at 15 significant digits. Double::to_string
// gives the shortest roundtrip decimal, which we round as a digit string so
// ROUND(2.675, 2) = 2.68 instead of the naive binary 2.67.

struct Dec {
  neg : Bool
  digits : String // normalized: no leading/trailing zeros; "0" for zero
  exp : Int // value = d0.d1d2... * 10^exp
}

let digit_chars : Array[Char] = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9']

fn dec_zero() -> Dec {
  { neg: false, digits: "0", exp: 0 }
}

fn dec_of_double(d : Double) -> Dec {
  if d == 0.0 {
    return dec_zero()
  }
  let chars = Array::from_iter(d.to_string().iter())
  let n = chars.length()
  let mut i = 0
  let mut neg = false
  if chars[0] == '-' {
    neg = true
    i = 1
  }
  let mut e_pos = n
  for j in i..<n {
    if chars[j] == 'e' || chars[j] == 'E' {
      e_pos = j
      break
    }
  }
  let mut exp_part = 0
  if e_pos < n {
    let mut j = e_pos + 1
    let mut esign = 1
    if chars[j] == '+' {
      j += 1
    } else if chars[j] == '-' {
      esign = -1
      j += 1
    }
    while j < n {
      exp_part = exp_part * 10 + (chars[j].to_int() - '0'.to_int())
      j += 1
    }
    exp_part *= esign
  }
  let ds : Array[Char] = []
  let mut dot = -1
  for j in i..<e_pos {
    if chars[j] == '.' {
      dot = ds.length()
    } else {
      ds.push(chars[j])
    }
  }
  if dot < 0 {
    dot = ds.length()
  }
  let mut lead = 0
  while lead < ds.length() - 1 && ds[lead] == '0' {
    lead += 1
  }
  let exp = dot - lead - 1 + exp_part
  let mut end = ds.length()
  while end > lead + 1 && ds[end - 1] == '0' {
    end -= 1
  }
  { neg, digits: String::from_array(ds[lead:end]), exp }
}

// mode: 0 = half away from zero, 1 = away (up), 2 = truncate (down).
// keep = number of leading digits to retain; may be <= 0.
fn round_dec(d : Dec, keep : Int, mode : Int) -> Dec {
  if d.digits == "0" || keep >= d.digits.length() {
    return d
  }
  let n = d.digits.length()
  let ds : Array[Int] = []
  for ch in d.digits.iter() {
    ds.push(ch.to_int() - '0'.to_int())
  }
  if keep <= 0 {
    let decision = if keep == 0 { ds[0] } else { 0 }
    let up = match mode {
      0 => decision >= 5
      1 => true
      _ => false
    }
    if !up {
      return dec_zero()
    }
    return { neg: d.neg, digits: "1", exp: d.exp + 1 - keep }
  }
  let mut tail_nonzero = false
  for j in keep..<n {
    if ds[j] != 0 {
      tail_nonzero = true
      break
    }
  }
  let up = match mode {
    0 => ds[keep] >= 5
    1 => tail_nonzero
    _ => false
  }
  let mut kept : Array[Int] = []
  for j in 0..<keep {
    kept.push(ds[j])
  }
  let mut exp = d.exp
  if up {
    let mut j = keep - 1
    while j >= 0 {
      if kept[j] == 9 {
        kept[j] = 0
        j -= 1
      } else {
        kept[j] += 1
        break
      }
    }
    if j < 0 {
      let nk : Array[Int] = [1]
      for x in kept {
        nk.push(x)
      }
      kept = nk
      exp += 1
    }
  }
  while kept.length() > 1 && kept[kept.length() - 1] == 0 {
    let _ = kept.pop()
  }
  let mut s = ""
  for v in kept {
    s = s + digit_chars[v].to_string()
  }
  { neg: d.neg, digits: s, exp }
}

fn dec_to_double(d : Dec) -> Double {
  if d.digits == "0" {
    return 0.0
  }
  let mut s = if d.neg { "-" } else { "" }
  s = s + d.digits.substring(start=0, end=1)
  if d.digits.length() > 1 {
    s = s + "." + d.digits.substring(start=1)
  }
  s = s + "e" + d.exp.to_string()
  @string.parse_double(s[:]) catch { _ => 0.0 }
}

fn dec_to_fixed(d : Dec) -> String {
  let point = d.exp + 1
  let n = d.digits.length()
  if point <= 0 {
    let mut s = "0."
    for _ in 0..<(-point) {
      s = s + "0"
    }
    return s + d.digits
  }
  if point >= n {
    let mut s = d.digits
    for _ in 0..<(point - n) {
      s = s + "0"
    }
    return s
  }
  d.digits.substring(start=0, end=point) + "." + d.digits.substring(start=point)
}

// Excel implicit number->text conversion ("General" as used by & and
// CONCAT): round to 15 significant digits, then fixed notation while the
// decimal exponent is within [-18, 19], scientific otherwise. Scientific
// mantissas drop trailing zeros; fixed integers are padded with zeros.
pub fn number_to_text(d : Double) -> String {
  let dec = round_dec(dec_of_double(d), 15, 0)
  if dec.digits == "0" {
    return "0"
  }
  let sign = if dec.neg { "-" } else { "" }
  if dec.exp >= 20 || dec.exp <= -19 {
    let mut mant = dec.digits.substring(start=0, end=1)
    if dec.digits.length() > 1 {
      mant = mant + "." + dec.digits.substring(start=1)
    }
    let e = dec.exp
    let esign = if e < 0 { "-" } else { "+" }
    let ea = if e < 0 { -e } else { e }
    return sign + mant + "E" + esign + ea.to_string()
  }
  sign + dec_to_fixed(dec)
}

pub fn round_excel(d : Double, digits : Int, mode : Int) -> Double {
  if d == 0.0 {
    return 0.0
  }
  let dec = round_dec(dec_of_double(d), 15, 0)
  let keep = dec.exp + 1 + digits
  dec_to_double(round_dec(dec, keep, mode))
}
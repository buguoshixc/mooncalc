// TEXT numeric subset: 0 # ? . , % , quoted literals, \ escapes, and up to
// three sections (positive;negative;zero). Anything else (date/time codes,
// colors, conditions, scientific, fractions, locale) fails loudly #VALUE!.

enum FmtTok {
  Zero
  Hash
  Quest
  Dot
  Comma
  Percent
  Lit(String)
}

fn is_digit_tok(t : FmtTok) -> Bool {
  match t {
    Zero | Hash | Quest => true
    _ => false
  }
}

fn split_sections(fmt : String) -> Array[String] {
  let sections : Array[String] = []
  let mut cur = ""
  let mut in_quote = false
  let mut escaped = false
  for c in fmt.iter() {
    if escaped {
      cur = cur + c.to_string()
      escaped = false
      continue
    }
    if c == '\\' {
      cur = cur + c.to_string()
      escaped = true
      continue
    }
    if c == '"' {
      in_quote = !in_quote
      cur = cur + c.to_string()
      continue
    }
    if c == ';' && !in_quote {
      sections.push(cur)
      cur = ""
    } else {
      cur = cur + c.to_string()
    }
  }
  sections.push(cur)
  sections
}

fn tokenize_section(s : String) -> Result[Array[FmtTok], XlError] {
  let chars = Array::from_iter(s.iter())
  let toks : Array[FmtTok] = []
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c == '0' {
      toks.push(Zero)
      i += 1
    } else if c == '#' {
      toks.push(Hash)
      i += 1
    } else if c == '?' {
      toks.push(Quest)
      i += 1
    } else if c == '.' {
      toks.push(Dot)
      i += 1
    } else if c == ',' {
      toks.push(Comma)
      i += 1
    } else if c == '%' {
      toks.push(Percent)
      i += 1
    } else if c == '"' {
      let mut j = i + 1
      let mut lit = ""
      while j < chars.length() && chars[j] != '"' {
        lit = lit + chars[j].to_string()
        j += 1
      }
      if j >= chars.length() {
        return Err(XlError::Value)
      }
      toks.push(Lit(lit))
      i = j + 1
    } else if c == '\\' || c == '_' {
      if i + 1 >= chars.length() {
        return Err(XlError::Value)
      }
      toks.push(Lit(if c == '_' { " " } else { chars[i + 1].to_string() }))
      i += 2
    } else if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '*' ||
      c == '[' || c == ']' {
      return Err(XlError::Value)
    } else {
      toks.push(Lit(c.to_string()))
      i += 1
    }
  }
  Ok(toks)
}

fn render_int(
  int_str : String,
  int_zeros : Int,
  int_digits : Int,
  has_quest : Bool,
  grouping : Bool
) -> String {
  let mut s = int_str
  if s == "0" && int_zeros == 0 {
    let mut out = ""
    if has_quest {
      for _ in 0..<int_digits {
        out = out + " "
      }
    }
    return out
  }
  while s.length() < int_zeros {
    s = "0" + s
  }
  if grouping {
    let cs = Array::from_iter(s.iter())
    let mut g = ""
    for i in 0..<cs.length() {
      let from_right = cs.length() - i
      g = g + cs[i].to_string()
      if from_right > 1 && from_right % 3 == 1 {
        g = g + ","
      }
    }
    s = g
  }
  if has_quest {
    while s.length() < int_digits {
      s = " " + s
    }
  }
  s
}

fn render_frac(frac_str : String, placeholders : Array[FmtTok]) -> String {
  let fc = Array::from_iter(frac_str.iter())
  let mut last_nonzero = -1
  for i in 0..<fc.length() {
    if fc[i] != '0' {
      last_nonzero = i
    }
  }
  let mut out = ""
  for i in 0..<placeholders.length() {
    let ch = if i < fc.length() { fc[i] } else { '0' }
    if ch == '0' && i > last_nonzero {
      match placeholders[i] {
        Hash => ()
        Quest => out = out + " "
        _ => out = out + "0"
      }
    } else {
      out = out + ch.to_string()
    }
  }
  out
}

pub fn text_format(d : Double, fmt : String) -> Result[String, XlError] {
  if !d.is_finite() {
    return Err(XlError::Value)
  }
  if fmt.compare_ignore_ascii_case("general") == 0 {
    return Ok(number_to_text(d))
  }
  let sections = split_sections(fmt)
  if sections.length() > 3 {
    return Err(XlError::Value)
  }
  let idx = if d > 0.0 {
    0
  } else if d < 0.0 {
    if sections.length() >= 2 { 1 } else { 0 }
  } else if sections.length() == 3 {
    2
  } else {
    0
  }
  let toks = match tokenize_section(sections[idx]) {
    Ok(t) => t
    Err(e) => return Err(e)
  }
  let mut dot_pos = -1
  let mut int_zeros = 0
  let mut int_digits = 0
  let mut frac_digits = 0
  let mut int_quest = false
  let mut percents = 0
  let mut trailing_commas = 0
  let mut grouping = false
  let frac_toks : Array[FmtTok] = []
  for i in 0..<toks.length() {
    match toks[i] {
      Zero | Hash | Quest => {
        if dot_pos < 0 {
          int_digits += 1
          if toks[i] is Zero {
            int_zeros += 1
          }
          if toks[i] is Quest {
            int_quest = true
          }
        } else {
          frac_digits += 1
          frac_toks.push(toks[i])
        }
      }
      Dot => {
        if dot_pos >= 0 {
          return Err(XlError::Value)
        }
        dot_pos = i
      }
      Percent => percents += 1
      _ => ()
    }
  }
  for i in 0..<toks.length() {
    if toks[i] is Comma {
      let mut p = i - 1
      while p >= 0 && toks[p] is Comma {
        p -= 1
      }
      if p < 0 || !is_digit_tok(toks[p]) {
        return Err(XlError::Value)
      }
      let mut q = i + 1
      while q < toks.length() && toks[q] is Comma {
        q += 1
      }
      if q < toks.length() && is_digit_tok(toks[q]) {
        grouping = true
      } else {
        trailing_commas += 1
      }
    }
  }
  let mut v = d.abs()
  for _ in 0..<percents {
    v *= 100.0
  }
  for _ in 0..<trailing_commas {
    v /= 1000.0
  }
  let rounded = round_excel(v, frac_digits, 0)
  let int_part = rounded.floor()
  let int_str = dec_to_fixed(dec_of_double(int_part))
  let mut frac_str = ""
  if frac_digits > 0 {
    let f = round_excel(rounded - int_part, frac_digits, 0)
    let fs = dec_to_fixed(dec_of_double(f))
    frac_str = if fs.has_prefix("0.") { fs.substring(start=2) } else { "" }
    while frac_str.length() < frac_digits {
      frac_str = frac_str + "0"
    }
  }
  let int_rendered = render_int(int_str, int_zeros, int_digits, int_quest, grouping)
  let frac_rendered = if frac_digits > 0 {
    render_frac(frac_str, frac_toks)
  } else {
    ""
  }
  let mut out = ""
  let mut int_done = false
  let mut frac_done = false
  let mut seen_dot = false
  for t in toks {
    match t {
      Zero | Hash | Quest =>
        if !seen_dot {
          if !int_done {
            out = out + int_rendered
            int_done = true
          }
        } else if !frac_done {
          out = out + frac_rendered
          frac_done = true
        }
      Dot => {
        seen_dot = true
        if frac_digits > 0 {
          out = out + "."
        }
      }
      Comma => ()
      Percent => out = out + "%"
      Lit(s) => out = out + s
    }
  }
  if sections.length() == 1 && d < 0.0 {
    out = "-" + out
  }
  Ok(out)
}
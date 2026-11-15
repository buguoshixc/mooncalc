// TEXT numeric subset: 0 # ? . , % , quoted literals, \ escapes, scientific
// notation (E+/E- mantissa/exponent), conditional sections ([>100]...), and up
// to three sections (positive;negative;zero). Date/time codes live further
// below; elapsed-time tokens ([h] [m] [s]) are part of the date/time subset.
// Anything else (colors, locale tags, fractions, locale names) fails loudly
// #VALUE!.

enum FmtTok {
  Zero
  Hash
  Quest
  Dot
  Comma
  Percent
  Exp(Char)
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
    } else if c == 'E' || c == 'e' {
      // Scientific notation must be followed by an explicit exponent sign:
      // "0.00E+00" / "0.00E-00"; a bare E is outside the subset.
      if i + 1 < chars.length() && (chars[i + 1] == '+' || chars[i + 1] == '-') {
        toks.push(Exp(chars[i + 1]))
        i += 2
      } else {
        return Err(XlError::Value)
      }
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

// ---------------------------------------------------------------------------
// Conditional sections: a section may start with [operator number], e.g.
// "[>100]0", "[<=0]-0.00". The prefix is stripped before tokenization; section
// selection uses criteria.mbt's operator/wildcard machinery (numeric compare).
// Colors / locale tags ([Red], [$-409]) reach the same prefix parser, fail its
// numeric-operand check, and stay loudly #VALUE!.

struct FmtCond {
  op : String
  operand : Double
}

struct FmtSection {
  cond : FmtCond?
  body : String
}

enum SectionChoice {
  // No conditional tags: section chosen by sign/zero.
  Pick(Int)
  // A conditional tag matched; carries that condition.
  CondPick(Int, FmtCond)
  // No condition matched; this condition-less section is the default.
  FallbackPick(Int)
  // Single conditional section, no match and no default: Excel falls back to
  // its General number text.
  GeneralPick(FmtCond)
}

// A condition is a "sign marker" when it is a comparison with zero
// ([>0], [>=0], [<0], [<=0]). Those sections render the absolute value and
// suppress Excel's automatic minus (corpus text-text-0131, probes w25).
fn is_sign_marker(c : FmtCond) -> Bool {
  c.operand == 0.0 &&
  (c.op == ">" || c.op == ">=" || c.op == "<" || c.op == "<=")
}

// Whether a condition could ever match a negative number. Excel's General
// fallback for a single false conditional section drops the minus exactly for
// such conditions (probes: TEXT(-50,"[>0]0.0") = "50" and
// TEXT(-50,"[>-10]0.0") = "50", but TEXT(-50,"[>1]0.0") = "-50" and
// TEXT(-50,"[=0]0.0") = "-50").
fn cond_can_match_negative(c : FmtCond) -> Bool {
  c.operand < 0.0 || (c.operand == 0.0 && c.op != "=")
}

fn is_format_condition(inner : String) -> Bool {
  let chars = Array::from_iter(inner.iter())
  if chars.length() == 0 {
    return false
  }
  let c = chars[0]
  c == '<' || c == '>' || c == '='
}

// A section may start with a conditional tag ([>100]), an elapsed token ([h])
// or a colour tag ([Red]). Only conditional tags are stripped here; elapsed
// tokens stay in the body for the date/time renderer and colour tags fail
// loudly in the tokenizer (outside the declared subset).
fn parse_section_prefix(section : String) -> Result[FmtSection, XlError] {
  let chars = Array::from_iter(section.iter())
  if chars.length() == 0 || chars[0] != '[' {
    return Ok({ cond: None, body: section })
  }
  let mut close = 1
  while close < chars.length() && chars[close] != ']' {
    close += 1
  }
  if close >= chars.length() || close == 1 {
    return Err(XlError::Value)
  }
  let inner = section.substring(start=1, end=close)
  if !is_format_condition(inner) {
    return Ok({ cond: None, body: section })
  }
  let crit = parse_criteria(Value::Text(inner))
  match crit.operand {
    Num(target) => Ok({
      cond: Some({ op: crit.op, operand: target }),
      body: section.substring(start=close + 1),
    })
    _ => Err(XlError::Value)
  }
}

fn section_has_cond(sections : Array[FmtSection]) -> Bool {
  for s in sections {
    if s.cond is Some(_) {
      return true
    }
  }
  false
}

// Selection rules adjudicated by the real-Excel 2024 corpus (probe rows
// text-text-0125..0141):
// - no condition tags: positive -> section 1, negative -> section 2, zero ->
//   section 3, each falling back to section 1 when absent;
// - with condition tags: the first matching condition wins; a condition-less
//   section is the default when no condition matches; if every section is
//   conditional and none matches, a single-section format falls back to
//   General text (TEXT(50,"[>100]0.00") = "50"), otherwise #VALUE!.
fn select_section(
  sections : Array[FmtSection],
  d : Double
) -> Result[SectionChoice, XlError] {
  let n = sections.length()
  if !section_has_cond(sections) {
    let idx = if d > 0.0 {
      0
    } else if d < 0.0 {
      if n >= 2 { 1 } else { 0 }
    } else if n == 3 {
      2
    } else {
      0
    }
    return Ok(Pick(idx))
  }
  let mut fallback = -1
  for i in 0..<n {
    match sections[i].cond {
      Some(c) =>
        if criteria_match(Value::Num(d), { op: c.op, operand: Value::Num(c.operand) }) {
          return Ok(CondPick(i, c))
        }
      None => if fallback < 0 {
        fallback = i
      }
    }
  }
  if fallback >= 0 {
    return Ok(FallbackPick(fallback))
  }
  if n == 1 {
    match sections[0].cond {
      Some(c) => return Ok(GeneralPick(c))
      None => ()
    }
  }
  Err(XlError::Value)
}

// True when a numeric section body contains at least one digit placeholder
// outside quoted literals. Excel does not prepend its automatic minus to a
// literal-only section (corpus text-text-0135: "[<-100]"small"" renders
// "small"), but does for an empty fallback section (probe y05: "-").
fn body_has_digit_placeholder(body : String) -> Bool {
  let chars = Array::from_iter(body.iter())
  let n = chars.length()
  let mut i = 0
  while i < n {
    let c = chars[i]
    if c == '"' {
      i += 1
      while i < n && chars[i] != '"' {
        i += 1
      }
      i += 1
    } else if c == '\\' || c == '_' {
      i += 2
    } else if c == '0' || c == '#' || c == '?' {
      return true
    } else {
      i += 1
    }
  }
  false
}

// True when a condition-stripped date/time section body consists only of
// elapsed tokens and literal separators: "[h]" and "[m]" -> true, but
// "[h]:mm" -> false because the plain mm is a minute/month date token.
fn body_is_elapsed_only(body : String) -> Bool {
  let chars = Array::from_iter(body.iter())
  let n = chars.length()
  let mut i = 0
  while i < n {
    let c = chars[i]
    if c == '"' {
      i += 1
      while i < n && chars[i] != '"' {
        i += 1
      }
      i += 1
    } else if c == '\\' || c == '_' {
      i += 2
    } else if c == '[' {
      let mut j = i + 1
      while j < n && chars[j] != ']' {
        j += 1
      }
      if j >= n {
        return false
      }
      if !is_elapsed_token(String::from_array(chars[i + 1:j])) {
        return false
      }
      i = j + 1
    } else if is_fmt_letter(c) {
      return false
    } else {
      i += 1
    }
  }
  true
}

fn body_single_elapsed_token(body : String) -> Bool {
  let chars = Array::from_iter(body.iter())
  let n = chars.length()
  if n < 3 || chars[0] != '[' || chars[n - 1] != ']' {
    return false
  }
  let mut close = 1
  while close < n && chars[close] != ']' {
    close += 1
  }
  close == n - 1 && is_elapsed_token(String::from_array(chars[1:close]))
}

// Render the mantissa/exponent pair of a scientific section. The mantissa is
// normalized to one integer digit plus `frac_digits` fraction digits (padding
// with zeros); the exponent carries the overflow from rounding (9.99 with
// "0.0E+00" -> 1.0E+01). `exp_width` is the number of exponent placeholders;
// wider actual exponents grow instead of being truncated.
fn render_scientific(
  toks : Array[FmtTok],
  exp_pos : Int,
  v : Double,
  frac_digits : Int,
  exp_width : Int
) -> String {
  let keep = 1 + frac_digits
  let dec = if v == 0.0 {
    dec_zero()
  } else {
    round_dec(dec_of_double(v), keep, 0)
  }
  let mut mant = dec.digits.substring(start=0, end=1)
  if frac_digits > 0 {
    let mut f = ""
    for k in 1..=frac_digits {
      f = f + (if k < dec.digits.length() {
        dec.digits.substring(start=k, end=k + 1)
      } else {
        "0"
      })
    }
    mant = mant + "." + f
  }
  let exp_val = dec.exp
  let sign_char = match toks[exp_pos] {
    Exp(c) => c
    _ => '+'
  }
  let sign = if exp_val < 0 {
    "-"
  } else if sign_char == '+' {
    "+"
  } else {
    ""
  }
  let ea = if exp_val < 0 { -exp_val } else { exp_val }
  let exp_str = sign + pad_num(ea, exp_width)
  let mut out = ""
  let mut placed_mant = false
  let mut placed_exp = false
  for i in 0..<toks.length() {
    match toks[i] {
      Zero | Hash | Quest =>
        if i < exp_pos {
          if !placed_mant {
            out = out + mant
            placed_mant = true
          }
        } else if !placed_exp {
          out = out + exp_str
          placed_exp = true
        }
      Dot => ()
      Comma => ()
      Percent => if i < exp_pos { out = out + "%" }
      Lit(s) => out = out + s
      Exp(_) => if !placed_exp {
        out = out + "E" + exp_str
        placed_exp = true
      }
    }
  }
  out
}

pub fn text_format(d : Double, fmt : String) -> Result[String, XlError] {
  if !d.is_finite() {
    return Err(XlError::Value)
  }
  if fmt.compare_ignore_ascii_case("general") == 0 {
    // zh-CN Excel rejects the English "General" keyword inside TEXT
    // (TEXT(123,"General") = #VALUE!), unlike plain number-to-text coercion.
    return Err(XlError::Value)
  }
  let raw_sections = split_sections(fmt)
  if is_date_time_format(fmt) {
    return text_format_date_time(d, raw_sections)
  }
  if raw_sections.length() > 3 {
    return Err(XlError::Value)
  }
  let sections : Array[FmtSection] = []
  for s in raw_sections {
    match parse_section_prefix(s) {
      Ok(sec) => sections.push(sec)
      Err(e) => return Err(e)
    }
  }
  let mut selected = -1
  let mut show_auto_minus = false
  match select_section(sections, d) {
    Ok(Pick(i)) => {
      selected = i
      show_auto_minus = sections.length() == 1 && d < 0.0
    }
    Ok(CondPick(i, c)) => {
      selected = i
      show_auto_minus = d < 0.0 && !is_sign_marker(c)
    }
    Ok(FallbackPick(i)) => {
      selected = i
      show_auto_minus = d < 0.0
    }
    Ok(GeneralPick(c)) => {
      // Out-of-subset guard: Excel's General text for |x| >= 1e11 uses a
      // 6-significant-digit scientific form; we refuse loudly instead of
      // emitting a different representation.
      if d.abs() >= 1.0e11 {
        return Err(XlError::Value)
      }
      return Ok(if cond_can_match_negative(c) {
        number_to_text(d.abs())
      } else {
        number_to_text(d)
      })
    }
    Err(e) => return Err(e)
  }
  let selected_body = sections[selected].body
  let toks = match tokenize_section(selected_body) {
    Ok(t) => t
    Err(e) => return Err(e)
  }
  // Locate the scientific exponent token (at most one) and validate its shape:
  // it needs at least one digit placeholder and no further dot/comma/E.
  let mut exp_pos = -1
  for i in 0..<toks.length() {
    match toks[i] {
      Exp(_) =>
        if exp_pos >= 0 {
          return Err(XlError::Value)
        } else {
          exp_pos = i
        }
      _ => ()
    }
  }
  let mantissa_end = if exp_pos >= 0 { exp_pos } else { toks.length() }
  let mut exp_width = 0
  if exp_pos >= 0 {
    for i in (exp_pos + 1)..<toks.length() {
      match toks[i] {
        Zero | Hash | Quest => exp_width += 1
        Dot | Comma | Exp(_) | Percent => return Err(XlError::Value)
        Lit(_) => ()
      }
    }
    if exp_width == 0 {
      return Err(XlError::Value)
    }
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
  for i in 0..<mantissa_end {
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
  for i in 0..<mantissa_end {
    if toks[i] is Comma {
      let mut p = i - 1
      while p >= 0 && toks[p] is Comma {
        p -= 1
      }
      if p < 0 || !is_digit_tok(toks[p]) {
        return Err(XlError::Value)
      }
      let mut q = i + 1
      while q < mantissa_end && toks[q] is Comma {
        q += 1
      }
      if q < mantissa_end && is_digit_tok(toks[q]) {
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
  if exp_pos >= 0 {
    let out = render_scientific(toks, exp_pos, v, frac_digits, exp_width)
    return Ok(if show_auto_minus { "-" + out } else { out })
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
      Exp(_) => ()
    }
  }
  // Automatic negative sign: shown for single-section formats and for
  // non-sign-marker conditional sections; suppressed by sign markers and by
  // multi-section negative sections (which carry their own sign rules).
  if show_auto_minus &&
    (selected_body.length() == 0 || body_has_digit_placeholder(selected_body)) {
    out = "-" + out
  }
  Ok(out)
}
// ---------------------------------------------------------------------------
// TEXT date/time format subset (Excel codes rendered in English, which matches
// the zh-CN Excel corpus: yyyy yy m mm mmm mmmm d dd ddd dddd h hh mm(minute)
// s ss AM/PM, quoted literals and \ escapes; 'aaa' locale weekday names are
// not implemented). Elapsed-time tokens [h] [hh] [m] [mm] [s] [ss] render the
// cumulative duration (days × 24 hours etc., not modulo a day). Date formats
// with sections (;) are rejected loudly.

let month_abbr : Array[String] = [
  "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov",
  "Dec",
]

let month_full : Array[String] = [
  "January", "February", "March", "April", "May", "June", "July", "August",
  "September", "October", "November", "December",
]

let day_abbr : Array[String] = ["Sat", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri"]

let day_full : Array[String] = [
  "Saturday", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday",
]

fn is_fmt_letter(c : Char) -> Bool {
  c == 'y' || c == 'Y' || c == 'm' || c == 'M' || c == 'd' || c == 'D' ||
  c == 'h' || c == 'H' || c == 's' || c == 'S' || c == 'a' || c == 'A'
}

fn is_elapsed_char(c : Char) -> Bool {
  c == 'h' || c == 'H' || c == 'm' || c == 'M' || c == 's' || c == 'S'
}

// Elapsed token contents: one or more repeats of the same h/m/s letter.
fn is_elapsed_token(inner : String) -> Bool {
  let chars = Array::from_iter(inner.iter())
  if chars.length() == 0 {
    return false
  }
  let unit = chars[0]
  if !is_elapsed_char(unit) {
    return false
  }
  for c in chars {
    if c.to_int() != unit.to_int() && c.to_int() != unit.to_int() - 32 &&
      c.to_int() - 32 != unit.to_int() {
      return false
    }
  }
  true
}

fn is_date_time_format(fmt : String) -> Bool {
  let chars = Array::from_iter(fmt.iter())
  let n = chars.length()
  let mut i = 0
  while i < n {
    let c = chars[i]
    if c == '"' {
      i += 1
      while i < n && chars[i] != '"' {
        i += 1
      }
      i += 1
    } else if c == '\\' || c == '_' {
      i += 2
    } else if c == '[' {
      // [h]/[m]/[s] elapsed tokens are date/time; a leading conditional tag
      // ([>100]) is skipped and scanning continues; colour/locale tags
      // ([Red], [$-409]) stay outside the date/time subset.
      let mut j = i + 1
      while j < n && chars[j] != ']' {
        j += 1
      }
      if j >= n {
        return false
      }
      let inner = String::from_array(chars[i + 1:j])
      if is_elapsed_token(inner) {
        return true
      }
      if is_format_condition(inner) {
        i = j + 1
      } else {
        return false
      }
    } else if is_fmt_letter(c) {
      return true
    } else {
      i += 1
    }
  }
  false
}

fn pad_num(v : Int, width : Int) -> String {
  let mut s = v.to_string()
  while s.length() < width {
    s = "0" + s
  }
  s
}

fn has_ampm(fmt : String) -> Bool {
  let n = fmt.length()
  let mut i = 0
  while i + 5 <= n {
    let sub = fmt.substring(start=i, end=i + 5)
    if sub.compare_ignore_ascii_case("AM/PM") == 0 {
      return true
    }
    i += 1
  }
  i = 0
  while i + 3 <= n {
    let sub = fmt.substring(start=i, end=i + 3)
    if sub.compare_ignore_ascii_case("A/P") == 0 {
      return true
    }
    i += 1
  }
  false
}

fn ampm_lower(fmt : String) -> Bool {
  let chars = Array::from_iter(fmt.iter())
  let n = chars.length()
  let mut i = 0
  while i < n {
    if chars[i] == 'a' {
      return true
    }
    i += 1
  }
  false
}

fn run_length(chars : Array[Char], start : Int, target : Char) -> Int {
  let n = chars.length()
  let want = target.to_int()
  let mut i = start
  while i < n && (chars[i].to_int() == want || chars[i].to_int() == want - 32) {
    i += 1
  }
  i - start
}

fn is_ampm_at(chars : Array[Char], i : Int) -> Int {
  // returns token length at i (0 if none) for AM/PM (5) or A/P (3)
  let n = chars.length()
  if i + 5 <= n {
    let s = String::from_array(chars[i:i + 5])
    if s.compare_ignore_ascii_case("AM/PM") == 0 {
      return 5
    }
  }
  if i + 3 <= n {
    let s = String::from_array(chars[i:i + 3])
    if s.compare_ignore_ascii_case("A/P") == 0 {
      return 3
    }
  }
  0
}

fn render_elapsed(
  chars : Array[Char],
  start : Int,
  whole : Double,
  total_secs : Int
) -> Result[(String, Char, Int), XlError] {
  // chars[start] == '['; find the closing bracket and render the cumulative
  // value (days are NOT wrapped modulo 24 hours / 60 minutes / 60 seconds).
  let n = chars.length()
  let mut j = start + 1
  while j < n && chars[j] != ']' {
    j += 1
  }
  if j >= n || j == start + 1 {
    return Err(XlError::Value)
  }
  let inner = String::from_array(chars[start + 1:j])
  if !is_elapsed_token(inner) {
    return Err(XlError::Value)
  }
  let run = inner.length()
  let unit = chars[start + 1]
  let days = whole.to_int()
  let text = if unit == 'h' || unit == 'H' {
    pad_num(days * 24 + total_secs / 3600, if run >= 2 { 2 } else { 1 })
  } else if unit == 'm' || unit == 'M' {
    pad_num(days * 1440 + total_secs / 60, if run >= 2 { 2 } else { 1 })
  } else {
    pad_num(days * 86400 + total_secs, if run >= 2 { 2 } else { 1 })
  }
  Ok((text, unit, j + 1))
}

// Date/time formats support the same sign/condition section selection as
// numeric formats (probe text-text-0141: TEXT(1,"yyyy;mm") = "1900"). A
// selected numeric section of a mixed format keeps numeric meaning. Negative
// values may only be rendered by elapsed-only formats (probe text-text-0122/
// 0123: TEXT(-0.5,"[h]") = "-12" but TEXT(-1.5,"[h]:mm") = #VALUE!), with the
// automatic minus suppressed when a conditional tag selected the section.
fn text_format_date_time(
  d : Double,
  raw_sections : Array[String]
) -> Result[String, XlError] {
  if raw_sections.length() > 3 {
    return Err(XlError::Value)
  }
  let sections : Array[FmtSection] = []
  for s in raw_sections {
    match parse_section_prefix(s) {
      Ok(sec) => sections.push(sec)
      Err(e) => return Err(e)
    }
  }
  let mut selected = -1
  let mut signed_numeric = false
  match select_section(sections, d) {
    Ok(Pick(i)) => {
      selected = i
      signed_numeric = sections.length() == 1 && d < 0.0
    }
    Ok(CondPick(i, c)) => {
      selected = i
      signed_numeric = d < 0.0 && !is_sign_marker(c)
    }
    Ok(FallbackPick(i)) => {
      selected = i
      signed_numeric = d < 0.0
    }
    Ok(GeneralPick(c)) => {
      if d.abs() >= 1.0e11 {
        return Err(XlError::Value)
      }
      return Ok(if cond_can_match_negative(c) {
        number_to_text(d.abs())
      } else {
        number_to_text(d)
      })
    }
    Err(e) => return Err(e)
  }
  let body = sections[selected].body
  if !is_date_time_format(body) {
    // Mixed formats such as "[h];0" or "0;yyyy": the chosen section is a
    // numeric format, so delegate (preserving the sign rules of the choice).
    return if d < 0.0 && signed_numeric {
      text_format(d, body)
    } else {
      text_format(d.abs(), body)
    }
  }
  if d < 0.0 {
    // Negative values: only elapsed-only sections can render; the automatic
    // minus is kept only for a single elapsed token (probe text-text-0122:
    // TEXT(-0.5,"[h]") = "-12").
    if sections.length() == 1 && !section_has_cond(sections) {
      if body_single_elapsed_token(body) {
        match render_date_time(-d, body) {
          Ok(s) => return Ok("-" + s)
          Err(e) => return Err(e)
        }
      }
      return Err(XlError::Value)
    }
    if body_is_elapsed_only(body) {
      return render_date_time(-d, body)
    }
    return Err(XlError::Value)
  }
  render_date_time(d, body)
}

fn render_date_time(d : Double, fmt : String) -> Result[String, XlError] {
  let chars = Array::from_iter(fmt.iter())
  let n = chars.length()
  let mut whole = d.trunc()
  let mut ymd = match serial_to_ymd(whole) {
    Err(_) => return Err(XlError::Value)
    Ok(v) => v
  }
  let mut total_secs = ((d - whole) * 86400.0).round().to_int()
  if total_secs >= 86400 {
    total_secs -= 86400
    whole += 1.0
    ymd = match serial_to_ymd(whole) {
      Err(_) => return Err(XlError::Value)
      Ok(v) => v
    }
  }
  if total_secs < 0 {
    return Err(XlError::Value)
  }
  let (year, month, day) = ymd
  let hour24 = total_secs / 3600
  let minute = (total_secs % 3600) / 60
  let second = total_secs % 60
  let hour12 = if hour24 % 12 == 0 { 12 } else { hour24 % 12 }
  let use_ampm = has_ampm(fmt)
  let lower_ampm = ampm_lower(fmt)
  let hour = if use_ampm { hour12 } else { hour24 }
  let wd = ((whole.to_int() % 7) + 7) % 7
  let mut out = ""
  let mut i = 0
  let mut seen_time = false

  while i < n {
    let c = chars[i]
    if c == '"' {
      i += 1
      while i < n && chars[i] != '"' {
        out = out + chars[i].to_string()
        i += 1
      }
      i += 1
    } else if c == '\\' {
      if i + 1 < n {
        out = out + chars[i + 1].to_string()
      }
      i += 2
    } else if c == '_' {
      out = out + " "
      i += 2
    } else if c == '[' {
      match render_elapsed(chars, i, whole, total_secs) {
        Err(e) => return Err(e)
        Ok((text, unit, next)) => {
          out = out + text
          if unit == 'h' || unit == 'H' || unit == 's' || unit == 'S' {
            seen_time = true
          }
          i = next
        }
      }
    } else if is_ampm_at(chars, i) > 0 {
      let tok = is_ampm_at(chars, i)
      let s = if hour24 < 12 { "AM" } else { "PM" }
      out = out + (if lower_ampm { lower_text(s) } else { s })
      i += tok
    } else if c == 'y' || c == 'Y' {
      let run = run_length(chars, i, 'y')
      if run >= 3 {
        out = out + pad_num(year, 4)
      } else if run == 2 {
        out = out + pad_num(year % 100, 2)
      } else {
        out = out + (year % 100).to_string()
      }
      i += run
    } else if c == 'm' || c == 'M' {
      let run = run_length(chars, i, 'm')
      let mut is_minute = seen_time
      if !is_minute {
        // m/mm is a minute when the next format code is s/ss (separators such
        // as ":" "." "/" " " are skipped): "mm:ss", "m:ss".
        let mut j = i + run
        while j < n &&
          (chars[j] == ':' ||
            chars[j] == '.' ||
            chars[j] == '/' ||
            chars[j] == ' ' ||
            chars[j] == '-') {
          j += 1
        }
        if j < n && (chars[j] == 's' || chars[j] == 'S') {
          is_minute = true
        }
      }
      if is_minute {
        if run >= 2 {
          out = out + pad_num(minute, 2)
        } else {
          out = out + minute.to_string()
        }
      } else if run >= 4 {
        out = out + month_full[month - 1]
      } else if run == 3 {
        out = out + month_abbr[month - 1]
      } else if run == 2 {
        out = out + pad_num(month, 2)
      } else {
        out = out + month.to_string()
      }
      i += run
    } else if c == 'd' || c == 'D' {
      let run = run_length(chars, i, 'd')
      if run >= 4 {
        out = out + day_full[wd]
      } else if run == 3 {
        out = out + day_abbr[wd]
      } else if run == 2 {
        out = out + pad_num(day, 2)
      } else {
        out = out + day.to_string()
      }
      i += run
    } else if c == 'h' || c == 'H' {
      let run = run_length(chars, i, 'h')
      if run >= 2 {
        out = out + pad_num(hour, 2)
      } else {
        out = out + hour.to_string()
      }
      seen_time = true
      i += run
    } else if c == 's' || c == 'S' {
      let run = run_length(chars, i, 's')
      if run >= 2 {
        out = out + pad_num(second, 2)
      } else {
        out = out + second.to_string()
      }
      seen_time = true
      i += run
    } else if c == 'a' || c == 'A' {
      return Err(XlError::Value)
    } else {
      out = out + c.to_string()
      i += 1
    }
  }
  Ok(out)
}

fn lower_text(s : String) -> String {
  let mut out = ""
  for c in s.iter() {
    if c >= 'A' && c <= 'Z' {
      out = out + ((c.to_int() + 32).unsafe_to_char()).to_string()
    } else {
      out = out + c.to_string()
    }
  }
  out
}

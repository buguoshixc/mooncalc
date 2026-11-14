pub enum Token {
  Number(Double)
  Str(String)
  BoolLit(Bool)
  ErrLit(@value.XlError)
  Ident(String)
  Op(String)
  LParen
  RParen
  Comma
  Colon
  Percent
} derive(Show, Debug, Eq)

fn is_ident_start(c : Char) -> Bool {
  @value.is_ascii_letter(c) || c == '$' || c == '_'
}

fn is_ident_char(c : Char) -> Bool {
  @value.is_ascii_letter(c) || @value.is_ascii_digit(c) || c == '$' || c == '_'
}

fn is_space(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

pub fn lex(input : String) -> Array[Token] raise ParseError {
  let chars : Array[Char] = Array::from_iter(input.iter())
  let n = chars.length()
  let toks : Array[Token] = []
  let mut i = 0
  while i < n && is_space(chars[i]) {
    i += 1
  }
  if i < n && chars[i] == '=' {
    i += 1
  }
  while i < n {
    let c = chars[i]
    if is_space(c) {
      i += 1
      continue
    }
    if @value.is_ascii_digit(c) ||
      (c == '.' && i + 1 < n && @value.is_ascii_digit(chars[i + 1])) {
      let start = i
      while i < n && @value.is_ascii_digit(chars[i]) {
        i += 1
      }
      if i < n && chars[i] == '.' {
        i += 1
        while i < n && @value.is_ascii_digit(chars[i]) {
          i += 1
        }
      }
      if i < n && (chars[i] == 'e' || chars[i] == 'E') {
        i += 1
        if i < n && (chars[i] == '+' || chars[i] == '-') {
          i += 1
        }
        if i >= n || !@value.is_ascii_digit(chars[i]) {
          raise ParseError("bad exponent at position " + i.to_string())
        }
        while i < n && @value.is_ascii_digit(chars[i]) {
          i += 1
        }
      }
      let text = String::from_array(chars[start:i])
      let d = @string.parse_double(text[:]) catch {
        _ => raise ParseError("bad number: " + text)
      }
      toks.push(Number(@value.excel_precision(d)))
      continue
    }
    if c == '"' {
      i += 1
      let buf : Array[Char] = []
      let mut closed = false
      while i < n {
        let ch = chars[i]
        if ch == '"' {
          if i + 1 < n && chars[i + 1] == '"' {
            buf.push('"')
            i += 2
          } else {
            i += 1
            closed = true
            break
          }
        } else {
          buf.push(ch)
          i += 1
        }
      }
      if !closed {
        raise ParseError("unterminated string literal")
      }
      toks.push(Str(String::from_array(buf[:])))
      continue
    }
    if c == '#' {
      let start = i
      i += 1
      while i < n &&
        (@value.is_ascii_letter(chars[i]) ||
          @value.is_ascii_digit(chars[i]) ||
          chars[i] == '/' ||
          chars[i] == '!' ||
          chars[i] == '?') {
        i += 1
      }
      let text = @value.ascii_upper(String::from_array(chars[start:i]))
      match @value.XlError::parse(text) {
        Some(e) => toks.push(ErrLit(e))
        None => raise ParseError("unknown error literal: " + text)
      }
      continue
    }
    if is_ident_start(c) {
      let start = i
      while i < n && is_ident_char(chars[i]) {
        i += 1
      }
      let raw = String::from_array(chars[start:i])
      let up = @value.ascii_upper(raw)
      if up == "TRUE" {
        toks.push(BoolLit(true))
      } else if up == "FALSE" {
        toks.push(BoolLit(false))
      } else {
        toks.push(Ident(raw))
      }
      continue
    }
    if c == '<' {
      if i + 1 < n && chars[i + 1] == '=' {
        toks.push(Op("<="))
        i += 2
      } else if i + 1 < n && chars[i + 1] == '>' {
        toks.push(Op("<>"))
        i += 2
      } else {
        toks.push(Op("<"))
        i += 1
      }
      continue
    }
    if c == '>' {
      if i + 1 < n && chars[i + 1] == '=' {
        toks.push(Op(">="))
        i += 2
      } else {
        toks.push(Op(">"))
        i += 1
      }
      continue
    }
    match c {
      '=' => toks.push(Op("="))
      '+' => toks.push(Op("+"))
      '-' => toks.push(Op("-"))
      '*' => toks.push(Op("*"))
      '/' => toks.push(Op("/"))
      '^' => toks.push(Op("^"))
      '&' => toks.push(Op("&"))
      '(' => toks.push(LParen)
      ')' => toks.push(RParen)
      ',' => toks.push(Comma)
      ':' => toks.push(Colon)
      '%' => toks.push(Percent)
      _ => raise ParseError("unexpected character: " + c.to_string())
    }
    i += 1
  }
  toks
}
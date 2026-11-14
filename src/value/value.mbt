pub(all) enum XlError {
  Div0
  NA
  Name
  Null
  Num
  Ref
  Value
} derive(Show, Debug, Eq)

pub fn XlError::to_string(self : XlError) -> String {
  match self {
    Div0 => "#DIV/0!"
    NA => "#N/A"
    Name => "#NAME?"
    Null => "#NULL!"
    Num => "#NUM!"
    Ref => "#REF!"
    Value => "#VALUE!"
  }
}

pub fn XlError::parse(s : String) -> XlError? {
  match s {
    "#DIV/0!" => Some(Div0)
    "#N/A" => Some(NA)
    "#NAME?" => Some(Name)
    "#NULL!" => Some(Null)
    "#NUM!" => Some(Num)
    "#REF!" => Some(Ref)
    "#VALUE!" => Some(Value)
    _ => None
  }
}

pub(all) struct RangeValue {
  rows : Int
  cols : Int
  cells : Array[Value]
} derive(Show, Debug, Eq)

pub(all) enum Value {
  Num(Double)
  Text(String)
  Bool(Bool)
  Err(XlError)
  Blank
  Range(RangeValue)
} derive(Show, Debug, Eq)

pub fn Value::type_name(self : Value) -> String {
  match self {
    Num(_) => "number"
    Text(_) => "text"
    Bool(_) => "bool"
    Err(_) => "error"
    Blank => "blank"
    Range(_) => "range"
  }
}

pub(all) struct CellAddr {
  row : Int
  col : Int
  abs_row : Bool
  abs_col : Bool
} derive(Show, Debug, Eq)

pub let max_row : Int = 1048576

pub let max_col : Int = 16384

fn col_letters(col : Int) -> String {
  let labels = [
    "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N",
    "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
  ]
  let mut c = col
  let mut out = ""
  while c > 0 {
    let rem = (c - 1) % 26
    out = labels[rem] + out
    c = (c - 1) / 26
  }
  out
}

pub fn CellAddr::to_string(self : CellAddr) -> String {
  let dc = if self.abs_col { "$" } else { "" }
  let dr = if self.abs_row { "$" } else { "" }
  dc + col_letters(self.col) + dr + self.row.to_string()
}

pub fn CellAddr::key(self : CellAddr) -> String {
  col_letters(self.col) + self.row.to_string()
}

pub fn parse_addr(s : String) -> CellAddr? {
  let chars : Array[Char] = Array::from_iter(s.iter())
  let n = chars.length()
  let mut i = 0
  let mut abs_col = false
  if i < n && chars[i] == '$' {
    abs_col = true
    i += 1
  }
  let col_start = i
  while i < n && is_ascii_letter(chars[i]) {
    i += 1
  }
  let letter_count = i - col_start
  if letter_count == 0 || letter_count > 3 {
    return None
  }
  let mut col = 0
  for k = col_start; k < i; k = k + 1 {
    let v = chars[k].to_int()
    let upper = if v >= 97 { v - 32 } else { v }
    col = col * 26 + (upper - 64)
  }
  if col > max_col {
    return None
  }
  let mut abs_row = false
  if i < n && chars[i] == '$' {
    abs_row = true
    i += 1
  }
  let row_start = i
  while i < n && is_ascii_digit(chars[i]) {
    i += 1
  }
  if i == row_start || i != n {
    return None
  }
  let mut row = 0
  for k = row_start; k < i; k = k + 1 {
    row = row * 10 + (chars[k].to_int() - 48)
    if row > max_row {
      return None
    }
  }
  if row < 1 {
    return None
  }
  let addr : CellAddr = { row, col, abs_row, abs_col }
  Some(addr)
}

pub fn is_ascii_letter(c : Char) -> Bool {
  let v = c.to_int()
  (v >= 65 && v <= 90) || (v >= 97 && v <= 122)
}

pub fn is_ascii_digit(c : Char) -> Bool {
  let v = c.to_int()
  v >= 48 && v <= 57
}

pub fn ascii_upper(s : String) -> String {
  let lower = "abcdefghijklmnopqrstuvwxyz"
  let upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  let mut out = s
  for i = 0; i < 26; i = i + 1 {
    out = out.replace_all(
      old=lower.substring(start=i, end=i + 1),
      new=upper.substring(start=i, end=i + 1),
    )
  }
  out
}

pub fn ascii_lower(s : String) -> String {
  let lower = "abcdefghijklmnopqrstuvwxyz"
  let upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  let mut out = s
  for i = 0; i < 26; i = i + 1 {
    out = out.replace_all(
      old=upper.substring(start=i, end=i + 1),
      new=lower.substring(start=i, end=i + 1),
    )
  }
  out
}
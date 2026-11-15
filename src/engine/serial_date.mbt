// Excel 1900 date system with the Lotus 1-2-3 leap-year bug:
// serial 60 is the phantom 1900-02-29; serials >= 61 use epoch 1899-12-30,
// serials 1..59 use epoch 1899-12-31. Serial 0 is "1900-01-00".

fn fdiv(a : Int, b : Int) -> Int {
  if a >= 0 { a / b } else { (a - b + 1) / b }
}

// Howard Hinnant's civil-calendar algorithms (proleptic Gregorian).
fn days_from_civil(y0 : Int, m : Int, d : Int) -> Int {
  let y = if m <= 2 { y0 - 1 } else { y0 }
  let era = fdiv(y, 400)
  let yoe = y - era * 400
  let mp = if m > 2 { m - 3 } else { m + 9 }
  let doy = (153 * mp + 2) / 5 + d - 1
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  era * 146097 + doe - 719468
}

fn civil_from_days(z0 : Int) -> (Int, Int, Int) {
  let z = z0 + 719468
  let era = fdiv(z, 146097)
  let doe = z - era * 146097
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let y = yoe + era * 400
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp = (5 * doy + 2) / 153
  let d = doy - (153 * mp + 2) / 5 + 1
  let m = if mp < 10 { mp + 3 } else { mp - 9 }
  (if m <= 2 { y + 1 } else { y }, m, d)
}

/// Excel 序列日 → (年, 月, 日)。含 Lotus 幻影日：序列 60 = 1900-02-29，序列 0 = (1900,1,0)。
/// 非有限值或越界（<0 或 >2958465）返回 `#NUM!`；小数部分被截断。
pub fn serial_to_ymd(serial : Double) -> Result[(Int, Int, Int), XlError] {
  if !serial.is_finite() {
    return Err(XlError::Num)
  }
  let s = serial.trunc().to_int()
  if s < 0 || s > 2958465 {
    return Err(XlError::Num)
  }
  if s == 0 {
    return Ok((1900, 1, 0))
  }
  if s == 60 {
    return Ok((1900, 2, 29))
  }
  let days = if s <= 59 { s - 25568 } else { s - 25569 }
  Ok(civil_from_days(days))
}

/// Excel DATE()：年参数 0..1899 先 +1900，再按月溢出归一化（故 DATE(1900,0,1) 落在
/// 1899 → `#NUM!`）。序列日按 Excel/Lotus 日历计算（幻影日 1900-02-29 = 60，
/// DATE(1900,3,0) = 60、DATE(1900,2,30) = 61）。越界（序列 <0 或 >2958465）返回 `#NUM!`。
pub fn date_serial(y0 : Int, m0 : Int, d0 : Int) -> Result[Int, XlError] {
  let y_arg = if y0 >= 0 && y0 <= 1899 { y0 + 1900 } else { y0 }
  let total = y_arg * 12 + (m0 - 1)
  let y = fdiv(total, 12)
  let m = total - y * 12 + 1
  if y < 1900 || y > 9999 {
    return Err(XlError::Num)
  }
  let first_days = days_from_civil(y, m, 1)
  let first_serial = if y == 1900 && m <= 2 {
    first_days + 25568
  } else {
    first_days + 25569
  }
  let serial = first_serial + (d0 - 1)
  if serial < 0 || serial > 2958465 {
    return Err(XlError::Num)
  }
  Ok(serial)
}

/// proleptic Gregorian 月份天数。注意 1900 在此**不是**闰年：真实 Excel 的
/// EOMONTH(60,0) 返回 59，即 1900 年 2 月按 28 天计算（显示层仍保留幻影序列 60）。
/// 非法月份返回 0。
pub fn days_in_month(y : Int, m : Int) -> Int {
  if m == 2 {
    if (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 {
      29
    } else {
      28
    }
  } else if m == 4 || m == 6 || m == 9 || m == 11 {
    30
  } else if m >= 1 && m <= 12 {
    31
  } else {
    0
  }
}

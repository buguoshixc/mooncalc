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

pub fn date_serial(y0 : Int, m0 : Int, d0 : Int) -> Result[Int, XlError] {
  let total = y0 * 12 + (m0 - 1)
  let mut y = fdiv(total, 12)
  let m = total - y * 12 + 1
  if y >= 0 && y <= 1899 {
    y += 1900
  }
  if y < 0 || y > 9999 {
    return Err(XlError::Num)
  }
  let days = days_from_civil(y, m, 1) + (d0 - 1)
  let mut serial = days + 25569
  if serial < 61 {
    serial -= 1
  }
  if serial < 0 || serial > 2958465 {
    return Err(XlError::Num)
  }
  Ok(serial)
}
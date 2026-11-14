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

// Excel DATE(): a year argument in 0..1899 is shifted by +1900 *before*
// month normalization (so DATE(0,1,1) = DATE(1900,1,1), DATE(1900,0,1) is
// #NUM! because normalization lands in 1899). The serial is then computed as
// the serial of day 1 of the month plus (d - 1) on the Excel/Lotus calendar
// where 1900-02-29 exists as the phantom serial 60 (so DATE(1900,2,29) = 60,
// DATE(1900,3,0) = 60, DATE(1900,2,30) = 61).
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

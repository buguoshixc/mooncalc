// Provisional expectations for Batch-4 TEXT deepening (source: manual).
// Scientific notation / elapsed time / conditional sections are adjudicated by
// the authoritative corpus afterwards (probe rows in corpus/spec/text.tsv).

test "TEXT scientific notation E+ / E-" {
  assert_text(ev("=TEXT(12345,\"0.00E+00\")"), "1.23E+04")
  assert_text(ev("=TEXT(0.000123,\"0.00E+00\")"), "1.23E-04")
  assert_text(ev("=TEXT(1,\"0.00E+00\")"), "1.00E+00")
  assert_text(ev("=TEXT(0.5,\"0.0E+00\")"), "5.0E-01")
  // Rounding carry adjusts the exponent: 9.99 -> 1.0E+01.
  assert_text(ev("=TEXT(9.99,\"0.0E+00\")"), "1.0E+01")
  assert_text(ev("=TEXT(0,\"0.00E+00\")"), "0.00E+00")
  assert_text(ev("=TEXT(-12345,\"0.00E+00\")"), "-1.23E+04")
  // Exponent width is a minimum: fewer placeholders still grow.
  assert_text(ev("=TEXT(12345,\"0.00E+0\")"), "1.23E+4")
  assert_err(ev("=TEXT(1,\"0.0E\")"), @value.XlError::Value)
  assert_err(ev("=TEXT(1,\"0.0E+00.0\")"), @value.XlError::Value)
}

test "TEXT elapsed time [h] [m] [s]" {
  assert_text(ev("=TEXT(1.5,\"[h]:mm\")"), "36:00")
  assert_text(ev("=TEXT(1.5,\"[hh]:mm\")"), "36:00")
  assert_text(ev("=TEXT(1.5,\"[h]\")"), "36")
  assert_text(ev("=TEXT(1.5,\"[m]\")"), "2160")
  assert_text(ev("=TEXT(0.5,\"[m]:ss\")"), "720:00")
  assert_text(ev("=TEXT(0.25,\"[h]:mm:ss\")"), "6:00:00")
  assert_text(ev("=TEXT(1.5,\"[s]\")"), "129600")
  assert_text(ev("=TEXT(0.5,\"[h]\")"), "12")
}

test "TEXT conditional sections [>100]" {
  assert_text(ev("=TEXT(150,\"[>100]0\")"), "150")
  assert_text(ev("=TEXT(50,\"[>100]\"\"big\"\";\"\"small\"\"\")"), "small")
  assert_text(ev("=TEXT(150,\"[>100]\"\"big\"\";[<=100]\"\"small\"\"\")"), "big")
  assert_text(ev("=TEXT(50,\"[>100]\"\"big\"\";[<=100]\"\"small\"\"\")"), "small")
  assert_text(ev("=TEXT(-5,\"[<0]-0;[>=0]0\")"), "-5")
  assert_text(ev("=TEXT(5,\"[<0]-0;[>=0]0\")"), "5")
  // Conditional formats suppress the automatic negative sign.
  assert_text(ev("=TEXT(-5,\"[<0]0;[>=0]0\")"), "5")
  assert_text(ev("=TEXT(1234567,\"[>100]#,##0\")"), "1,234,567")
  assert_text(ev("=TEXT(150,\"[>200]0;0\")"), "150")
  // Colors and locale tags remain outside the subset.
  assert_err(ev("=TEXT(1,\"[Red]0\")"), @value.XlError::Value)
  assert_err(ev("=TEXT(1,\"[$-409]0\")"), @value.XlError::Value)
}

test "TEXT existing subset regression" {
  assert_text(ev("=TEXT(1234.5,\"#,##0.00\")"), "1,234.50")
  assert_text(ev("=TEXT(2.675,\"0.00\")"), "2.68")
  assert_text(ev("=TEXT(-1.5,\"0.0\")"), "-1.5")
  assert_text(ev("=TEXT(0.125,\"0.0%\")"), "12.5%")
  assert_text(ev("=TEXT(5,\"yyyy\")"), "1900")
  assert_text(ev("=TEXT(60,\"yyyy-mm-dd\")"), "1900-02-29")
  assert_text(ev("=TEXT(46340.5,\"yyyy-mm-dd hh:mm:ss\")"), "2026-11-14 12:00:00")
  assert_err(ev("=TEXT(123,\"General\")"), @value.XlError::Value)
  // Date/time sections are adjudicated by the corpus (text-text-0141):
  // a positive value uses the first section.
  assert_text(ev("=TEXT(1,\"yyyy;mm\")"), "1900")
  // Numeric section of a mixed format keeps numeric meaning.
  assert_text(ev("=TEXT(1.5,\"[h];0\")"), "36")
}

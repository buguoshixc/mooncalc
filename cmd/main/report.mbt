// Human-readable bench summary and --now parsing (shell-side only).

fn pct(n : Int, d : Int) -> String {
  if d == 0 {
    return "n/a"
  }
  let p = (n.to_double() / d.to_double() * 1000.0).round() / 10.0
  p.to_string() + "%"
}

fn render_counts(title : String, m : Map[String, (Int, Int)]) -> String {
  let keys : Array[String] = []
  for k, _ in m {
    keys.push(k)
  }
  keys.sort()
  let mut out = title + "\n"
  for k in keys {
    match m.get(k) {
      Some((t, p)) => out = out + "  " + k + ": " + p.to_string() + "/" + t.to_string() + " (" + pct(p, t) + ")\n"
      None => ()
    }
  }
  out
}

fn render_summary(rep : @codec.BenchReport) -> String {
  let mut out = "mooncalc bench: " + rep.passed.to_string() + "/" + rep.total.to_string() + " passed (" + pct(rep.passed, rep.total) + ")\n"
  out = out + render_counts("by source:", rep.by_source)
  out = out + render_counts("by tag:", rep.by_tag)
  let buckets : Array[String] = []
  for k, _ in rep.buckets {
    buckets.push(k)
  }
  buckets.sort()
  out = out + "buckets:"
  for k in buckets {
    match rep.buckets.get(k) {
      Some(n) => out = out + " " + k + "=" + n.to_string()
      None => ()
    }
  }
  out = out + "\n"
  let mut shown = 0
  for r in rep.results {
    if !r.passed {
      shown += 1
      out = out + "FAIL [" + r.id + "] " + r.formula + " (" + r.bucket + ")\n"
      out = out + "  expected: " + Json::stringify(r.expected) + "\n"
      out = out + "  actual:   " + Json::stringify(r.actual) + "\n"
      if r.detail != "" {
        out = out + "  detail:   " + r.detail + "\n"
      }
    }
  }
  if shown == 0 {
    out = out + "no diffs\n"
  }
  out
}

fn parse_int_arg(s : String) -> Int? {
  let mut n = 0
  if s.length() == 0 {
    return None
  }
  for c in s.iter() {
    if c < '0' || c > '9' {
      return None
    }
    n = n * 10 + (c.to_int() - 48)
  }
  Some(n)
}

fn split_str(s : String, sep : Char) -> Array[String] {
  let out : Array[String] = []
  let mut cur = ""
  for c in s.iter() {
    if c == sep {
      out.push(cur)
      cur = ""
    } else {
      cur = cur + c.to_string()
    }
  }
  out.push(cur)
  out
}

// Accepts an Excel serial number or ISO "YYYY-MM-DD[THH:MM:SS]".
fn parse_now_or_die(s : String) -> Double {
  if parse_double_arg(s) is Ok(d) {
    return d
  }
  let parts = split_str(s, 'T')
  let parts = if parts.length() == 1 { split_str(s, ' ') } else { parts }
  let date_parts = split_str(parts[0], '-')
  if date_parts.length() != 3 {
    die("--now must be a serial number or ISO date: " + s)
  }
  let y = match parse_int_arg(date_parts[0]) {
    Some(v) => v
    None => die("bad ISO year: " + s)
  }
  let m = match parse_int_arg(date_parts[1]) {
    Some(v) => v
    None => die("bad ISO month: " + s)
  }
  let d = match parse_int_arg(date_parts[2]) {
    Some(v) => v
    None => die("bad ISO day: " + s)
  }
  let serial = match @facade.date_serial(y, m, d) {
    Ok(v) => v.to_double()
    Err(_) => die("ISO date out of range: " + s)
  }
  if parts.length() == 1 {
    return serial
  }
  let time_parts = split_str(parts[1], ':')
  if time_parts.length() != 3 {
    die("bad ISO time: " + s)
  }
  let hh = match parse_int_arg(time_parts[0]) {
    Some(v) => v
    None => die("bad ISO hour: " + s)
  }
  let mm = match parse_int_arg(time_parts[1]) {
    Some(v) => v
    None => die("bad ISO minute: " + s)
  }
  let ss = match parse_int_arg(time_parts[2]) {
    Some(v) => v
    None => die("bad ISO second: " + s)
  }
  serial + (hh * 3600 + mm * 60 + ss).to_double() / 86400.0
}
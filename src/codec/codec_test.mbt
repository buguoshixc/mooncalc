fn jparse(s : String) -> Json {
  try @json.parse(s) catch { _ => panic() }
}

fn ok(s : String) -> Bool {
  match jparse(s).value("ok") {
    Some(j) => j.as_bool() == Some(true)
    None => false
  }
}

fn first_value(s : String) -> Json {
  let results = jparse(s).value("results").unwrap().as_array().unwrap()
  results[0].value("value").unwrap()
}

test "evaluate_json addr target" {
  let resp = evaluate_json(
    "{\"grid\":{\"A1\":2,\"A2\":3,\"B1\":{\"formula\":\"=A1*A2\"}},\"addr\":\"B1\"}",
  )
  assert_true(ok(resp))
  let v = first_value(resp)
  assert_eq(v.value("type").unwrap().as_string().unwrap(), "number")
  assert_eq(v.value("value").unwrap().as_number().unwrap(), 6.0)
}

test "evaluate_json formula target with coercion" {
  let resp = evaluate_json("{\"grid\":{},\"formula\":\"=SUM(\\\"3\\\",4)\"}")
  assert_true(ok(resp))
  assert_eq(first_value(resp).value("value").unwrap().as_number().unwrap(), 7.0)
}

test "evaluate_json recalc marks circular" {
  let resp = evaluate_json(
    "{\"grid\":{\"D1\":{\"formula\":\"=D1+1\"},\"D2\":{\"formula\":\"=D1+5\"}}}",
  )
  assert_true(ok(resp))
  let results = jparse(resp).value("results").unwrap().as_array().unwrap()
  assert_eq(results.length(), 2)
  let d1 = results[0]
  assert_eq(d1.value("target").unwrap().as_string().unwrap(), "D1")
  assert_eq(d1.value("value").unwrap().value("value").unwrap().as_number().unwrap(), 0.0)
  assert_eq(d1.value("circular").unwrap().as_bool().unwrap(), true)
  let d2 = results[1]
  assert_eq(d2.value("value").unwrap().value("value").unwrap().as_number().unwrap(), 5.0)
  assert_eq(d2.value("circular").unwrap().as_bool().unwrap(), false)
}

test "evaluate_json rejects bad input" {
  assert_false(ok(evaluate_json("not json")))
  let empty = evaluate_json("{\"grid\":{}}")
  assert_true(ok(empty))
  assert_eq(jparse(empty).value("results").unwrap().as_array().unwrap().length(), 0)
  assert_false(ok(evaluate_json("{\"grid\":{},\"formula\":\"=1+\"}")))
  assert_false(ok(evaluate_json("{\"grid\":{\"A0\":1}}")))
  assert_false(ok(evaluate_json("{\"grid\":{\"A1\":{\"error\":\"#BOGUS\"}}}")))
}

test "evaluate_json collects grid parse errors" {
  let resp = evaluate_json(
    "{\"grid\":{\"A1\":{\"formula\":\"=1+\"},\"A2\":{\"formula\":\"=A1+1\"}}}",
  )
  assert_true(ok(resp))
  let pes = jparse(resp).value("parse_errors").unwrap().as_array().unwrap()
  assert_eq(pes.length(), 1)
  assert_eq(pes[0].value("addr").unwrap().as_string().unwrap(), "A1")
}

fn corpus(records : String) -> Array[CaseRecord] {
  let j = jparse("{\"schema\":\"mooncalc-corpus/1\",\"records\":[" + records + "]}")
  match corpus_from_json(j) {
    Ok(rs) => rs
    Err(_) => panic()
  }
}

fn rec(id : String, formula : String, expected : String, tags : String) -> String {
  "{\"id\":\"" + id + "\",\"formula\":\"" + formula + "\",\"grid\":{},\"expected\":" +
  expected + ",\"tags\":[" + tags + "],\"source\":\"manual\"}"
}

test "bench buckets classify diffs" {
  let records = corpus(
    rec("t1", "=1+1", "{\"type\":\"number\",\"value\":2}", "\"math\"") + "," +
    rec(
      "t2",
      "=0.1+0.2",
      "{\"type\":\"number\",\"value\":0.3}",
      "\"math\"",
    ) + "," +
    rec("t3", "=1+1", "{\"type\":\"text\",\"value\":\"2\"}", "\"math\"") + "," +
    rec("t4", "=1+", "{\"type\":\"number\",\"value\":0}", "\"math\""),
  )
  let rep = run_bench(records, 1.0e-9, 1.0e-6, None)
  assert_eq(rep.total, 4)
  assert_eq(rep.passed, 1)
  assert_eq(rep.buckets.get("match"), Some(1))
  assert_eq(rep.buckets.get("numeric-tolerance"), Some(1))
  assert_eq(rep.buckets.get("type-mismatch"), Some(1))
  assert_eq(rep.buckets.get("parse-error"), Some(1))
  let report = report_to_json(rep)
  assert_eq(report.value("total").unwrap().as_number().unwrap(), 4.0)
  assert_eq(report.value("failures").unwrap().as_array().unwrap().length(), 3)
}

test "bench clock tolerance and filter" {
  let records = corpus(
    "{\"id\":\"c1\",\"formula\":\"=NOW()\",\"grid\":{},\"now\":46340.5," +
    "\"expected\":{\"type\":\"number\",\"value\":46340.5000001}," +
    "\"tags\":[\"clock\"],\"source\":\"manual\"}" + "," +
    rec("m1", "=1+1", "{\"type\":\"number\",\"value\":2}", "\"math\""),
  )
  let rep = run_bench(records, 1.0e-9, 1.0e-6, None)
  assert_eq(rep.passed, 2)
  assert_eq(rep.buckets.get("clock-tolerance"), Some(1))
  let filtered = run_bench(records, 1.0e-9, 1.0e-6, Some("math"))
  assert_eq(filtered.total, 1)
}

test "corpus decode validates schema and fields" {
  match corpus_from_json(jparse("{\"schema\":\"other/1\",\"records\":[]}")) {
    Err(_) => ()
    Ok(_) => panic()
  }
  match corpus_from_json(
    jparse("{\"schema\":\"mooncalc-corpus/1\",\"records\":[{\"id\":\"x\"}]}"),
  ) {
    Err(_) => ()
    Ok(_) => panic()
  }
}
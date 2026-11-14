// Corpus record decoding (mooncalc-corpus/1).

pub(all) struct CaseRecord {
  id : String
  formula : String
  grid : Grid
  now : Double?
  expected : Value
  tags : Array[String]
  source : String
  notes : String
} derive(Show, Debug)

fn decode_record(j : Json) -> CaseRecord raise CodecError {
  let id = jstr(jfield(j, "id"))
  let formula = jstr(jfield(j, "formula"))
  let grid = decode_grid(jfield(j, "grid"))
  let now = match j.value("now") {
    Some(nj) => Some(jnum(nj))
    None => None
  }
  let expected = decode_value(jfield(j, "expected"))
  let tags : Array[String] = match j.value("tags") {
    Some(tj) =>
      match tj.as_array() {
        Some(arr) => {
          let out : Array[String] = []
          for t in arr {
            out.push(jstr(t))
          }
          out
        }
        None => raise CodecError("tags must be an array")
      }
    None => []
  }
  let source = jstr(jfield(j, "source"))
  let notes = match j.value("notes") {
    Some(nj) => jstr(nj)
    None => ""
  }
  { id, formula, grid, now, expected, tags, source, notes }
}

pub fn record_from_json(j : Json) -> Result[CaseRecord, String] {
  try Ok(decode_record(j)) catch {
    CodecError(m) => Err(m)
  }
}

fn decode_corpus(j : Json) -> Array[CaseRecord] raise CodecError {
  let schema = jstr(jfield(j, "schema"))
  if schema != "mooncalc-corpus/1" {
    raise CodecError("unsupported corpus schema: " + schema)
  }
  let arr = match jfield(j, "records").as_array() {
    Some(a) => a
    None => raise CodecError("records must be an array")
  }
  let out : Array[CaseRecord] = []
  for r in arr {
    out.push(decode_record(r))
  }
  out
}

pub fn corpus_from_json(j : Json) -> Result[Array[CaseRecord], String] {
  try Ok(decode_corpus(j)) catch {
    CodecError(m) => Err(m)
  }
}
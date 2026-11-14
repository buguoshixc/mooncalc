struct FnSpec {
  min : Int
  max : Int
  call : (Ctx, Array[Thunk]) -> Value
}

fn lookup_fn(name : String) -> FnSpec? {
  match name {
    "IF" => Some({ min: 2, max: 3, call: fn_if })
    "AND" => Some({ min: 1, max: 30, call: fn_and })
    "OR" => Some({ min: 1, max: 30, call: fn_or })
    "NOT" => Some({ min: 1, max: 1, call: fn_not })
    "IFERROR" => Some({ min: 2, max: 2, call: fn_iferror })
    "ROUND" => Some({ min: 2, max: 2, call: fn_round })
    "ROUNDUP" => Some({ min: 2, max: 2, call: fn_roundup })
    "ROUNDDOWN" => Some({ min: 2, max: 2, call: fn_rounddown })
    "ABS" => Some({ min: 1, max: 1, call: fn_abs })
    "INT" => Some({ min: 1, max: 1, call: fn_int })
    "MOD" => Some({ min: 2, max: 2, call: fn_mod })
    "POWER" => Some({ min: 2, max: 2, call: fn_power })
    "SQRT" => Some({ min: 1, max: 1, call: fn_sqrt })
    "SUM" => Some({ min: 1, max: 30, call: fn_sum })
    "SUMIF" => Some({ min: 2, max: 3, call: fn_sumif })
    "SUMPRODUCT" => Some({ min: 1, max: 30, call: fn_sumproduct })
    "AVERAGE" => Some({ min: 1, max: 30, call: fn_average })
    "COUNT" => Some({ min: 1, max: 30, call: fn_count })
    "COUNTA" => Some({ min: 1, max: 30, call: fn_counta })
    "COUNTIF" => Some({ min: 2, max: 2, call: fn_countif })
    "MIN" => Some({ min: 1, max: 30, call: fn_min })
    "MAX" => Some({ min: 1, max: 30, call: fn_max })
    "MEDIAN" => Some({ min: 1, max: 30, call: fn_median })
    _ => None
  }
}
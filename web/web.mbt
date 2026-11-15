#export_name("evaluate_json")
pub fn evaluate_json(input : String) -> String {
  @codec.evaluate_json(input)
}

#export_name("explain_json")
pub fn explain_json(input : String) -> String {
  @codec.explain_json(input)
}

// Incremental recalc state lives in the shell (caller-owned per the facade
// contract); the codec and engine stay stateless.
struct IncState {
  mut inner : @facade.RecalcState?
}

let inc_state : IncState = { inner: None }

#export_name("recalc_incremental_json")
pub fn recalc_incremental_json(input : String) -> String {
  let (resp, state) = @codec.recalc_incremental_json(input, inc_state.inner)
  inc_state.inner = state
  resp
}
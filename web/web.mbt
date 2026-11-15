#export_name("evaluate_json")
pub fn evaluate_json(input : String) -> String {
  @codec.evaluate_json(input)
}

#export_name("explain_json")
pub fn explain_json(input : String) -> String {
  @codec.explain_json(input)
}
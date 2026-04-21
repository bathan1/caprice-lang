let strip_refinements = ref false
let refinement_positions : Ast.pos_span list ref = ref []

let push_refine_pos pos =
  refinement_positions := pos :: !refinement_positions

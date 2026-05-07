open Formula

type next =
  | Decide
  | Conflict of literal list
  | Implication of literal list * literal

let pp_next ~uid fd (next : next) : unit =
  match next with
  | Decide ->
      Format.fprintf fd "Decide"
  | Conflict clause ->
      Format.fprintf fd "Conflict (%a)" (pp_clause ~uid) clause
  | Implication (clause, lit) ->
      Format.fprintf fd "Implication (%a, %a)" (pp_clause ~uid) clause (pp_literal ~uid) lit

(** [find_next formula trail] iterates over the clauses from FORMULA and for each clause,
    subs in the literal values from TRAIL, and returns the [next] step based on
    the resulting substituted clause. The step will be...
    - [Decide] when there are no unit clauses after applying TRAIL to FORM
    - [Implication (clause, lit)]
    - [Conflict clause] when applying TRAIL to clause is inconsistent (i.e. substitution returns [Some] empty list)
*)
let find_next formula trail =
  let model = Trail.to_model trail in
  let rec search_empty
    (clauses : Formula.formula)
    (reason_clause : literal list)
    (lit : Formula.literal)
    : next =
    match clauses with
    | [] -> Implication (reason_clause, lit)
    | clause :: clauses' ->
      match Model.eval_clause clause model with
      | `Falsified -> Conflict clause
      | _ -> search_empty clauses' reason_clause lit
  in
  let rec search_unit (formula : Formula.formula) : next =
    match formula with
    | [] -> Decide
    | clause :: clauses' ->
      match Model.eval_clause clause model with
      | `Falsified -> Conflict clause
      | `Undecided [lit] -> search_empty clauses' clause lit
      | _ -> search_unit clauses'
  in
  search_unit formula

(** [bcp level trail formula] is the Boolean Constraint Propagation decision proc that searches
    for a satisfying truth table assignment for the given FORMULA STATE, bookkeeping LEVEL and TRAIL states
    per call

    Each call to bcp will either...
    - {b Implicate} a unit literal along with its reason clause
    - {b Decide} on a literal when there are no propagations left
    - Find a {b conflict clause} and return UNSAT if LEVEL is 0,
      or backtrack to some previous level < LEVEL and adds the
      learned conflict clauses to the FORMULA state
*)
let rec bcp (level : int) (trail : Trail.trail) (formula : Formula.formula) : literal list option =
  begin match find_next formula trail with
  | Decide ->
    let model = Trail.to_model trail in
    begin match Formula.find_free_variable_opt (List.map Formula.atom_from_literal model) formula with
    | None ->
      if Model.is_tautology formula model then Some model
      else None
    | Some x ->
      let lit = Formula.pos x in
      let decision_lvl = level + 1 in
      let trail' = Trail.decide lit decision_lvl trail in
      bcp decision_lvl trail' formula
    end
  | Conflict clause ->
    let conflict, backtrack_level = Trail.analyze_conflict ~conflict:clause level trail in
    if backtrack_level < 0 then
      None (* UNSAT *)
    else
      let trail', formula' =
        Trail.backtrack_learn ~conflict backtrack_level trail formula
      in
      bcp backtrack_level trail' formula'
  | Implication (clause, lit) ->
    let entry =
      { Trail.level ; lit ; reason = Propagated clause }
    in
    bcp level (entry :: trail) formula
  end

let cdcl formula = bcp 0 [] formula

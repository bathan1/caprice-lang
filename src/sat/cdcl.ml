open Utils
open Formula

type next =
(** [next] is the message type that indicates the next step 
    the main loop should propagate onto a solver state [t] *)
  | Decide
  | Conflict of literal list
  | Implication of literal list * literal

let pp_next fd (next : next) : unit =
  match next with
  | Decide ->
      Format.fprintf fd "Decide"
  | Conflict clause ->
      Format.fprintf fd "Conflict (%a)" pp_clause clause
  | Implication (clause, lit) ->
      Format.fprintf fd "Implication (%a, %a)" pp_clause clause pp_literal lit

(** [analyze_conflict conflict trail level] returns the first (minimum) unique-implication-point cut
    of decision level LEVEL that directs to the CONFLICT clause based on the TRAIL state *)
let rec analyze_conflict (level : int) (conflict : literal list) (trail : Trail.t list) : literal list * int =
  match List.filter (fun lit -> Trail.find_level lit trail = level) conflict with
  | [hd] ->
    if level = 0 then
      [], -1
    else
      let new_lvl =
        conflict
        |> List_utils.remove1 hd
        |> List.fold_left
             (fun lvl' lit -> max lvl' (Trail.find_level lit trail))
             0
      in
      conflict, new_lvl

  | current_level_lits ->
    let reason = Trail.find_reason current_level_lits trail in
    let conflict' = Formula.resolve_pair conflict reason in
    analyze_conflict level conflict' trail

(** [find_next trail form] iterates over the clauses from FORM and for each clause,
    subs in the literal values from TRAIL, and returns the [next] step based on
    the resulting substituted clause. The step step will be...
    - [Decide] when there are no unit clauses after applying TRAIL to FORM
    - [Implication (unit_clause, lit)] if the resulting clause is a unit clause
    - [Conflict clause] when applying TRAIL to clause is inconsistent (i.e. substitution returns [Some] empty list) *)
let find_next (trail : Trail.t list) (form : Formula.t) : next =
  let substitute =
    trail
    |> Trail.to_model
    |> Model.use_clause
  in
  let rec search_empty (clauses : Formula.t) (unit_clause : literal list) (lit : Formula.literal) : next =
    match clauses with
    | [] -> Implication (unit_clause, lit)
    | clause :: clauses' ->
      match substitute ~clause with
      | Some [] -> Conflict clause
      | _ -> search_empty clauses' unit_clause lit
  in
  let rec search_unit (form : Formula.t) : next =
    match form with
    | [] -> Decide
    | clause :: clauses' ->
      match substitute ~clause with
      | Some [] -> Conflict clause
      | Some [lit] -> search_empty clauses' clause lit
      | _ -> search_unit clauses'
  in
  search_unit form

let rec bcp (level : int) (trail : Trail.t list) (form : Formula.t) : literal list option =
  let model = Trail.to_model trail in
  begin match find_next trail form with
  | Decide ->
    begin match Formula.find_free_variable (List.map Formula.key_from_lit model) form with
    | None -> 
      if Model.is_tautology model ~form then Some model
      else None
    | Some x -> decide x (level + 1) trail form
    end
  | Conflict clause ->
    let conflict, backtrack_level = analyze_conflict level clause trail in
    if backtrack_level < 0 then 
      None (* UNSAT *)
    else
      backtrack_learn backtrack_level conflict trail form
  | Implication (clause, lit) ->
    let entry =
      { Trail.level; lit; reason = Propagated clause }
    in
    bcp level (entry :: trail) form
  end

and backtrack_learn
  (backtrack_level : int)
  (conflict : literal list)
  (trail : Trail.t list)
  (form : Formula.t)
  : literal list option =
  let trail' =
    Trail.backtrack backtrack_level trail
  in
  let form' =
    Formula.conjoin1 form conflict
  in
  bcp backtrack_level trail' form'

and decide 
  (x : Uid.t) 
  (level : int)
  (trail : Trail.t list) 
  (form : Formula.t) 
  : literal list option =
  let entry = { level ; Trail.lit = Formula.Pos x ; reason = Decided } in
  bcp level (entry :: trail) form

let cdcl (form : Formula.t) : literal list option =
  Printf.printf "[cdcl]: input = %s\n" (Formula.to_string form);
  bcp 0 [] form

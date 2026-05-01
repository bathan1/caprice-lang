open Formula
open Utils

type t = 
(** [Cdcl.t] is the solver state that encodes the CDCL decision graph state which tracks:
    - current decision LEVEL
    - Formula state CLAUSES
    - the clauses LEARNED from discovered conflicts *)
  { level : int
  ; clauses : Formula.t
  ; learned : Formula.t
  }

type next =
(** [next] is the message type that indicates the next step 
    the main loop should propagate onto a solver state [t] *)
  | Decide
  | Conflict of clause
  | Implication of clause * literal

(** [analyze_conflict conflict trail level] returns the first (minimum) unique-implication-point cut
    of decision level LEVEL that directs to the CONFLICT clause based on the TRAIL state *)
let rec analyze_conflict (conflict : clause) (trail : Trail.t list) (level : int) : clause * int =
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
    analyze_conflict conflict' trail level

let find_unit (trail : Trail.t list) (form : Formula.t) : next =
  let substitute =
    trail
    |> Trail.to_model
    |> Model.use_clause
  in
  let rec search_empty (clauses : clause list) (unit_clause : clause) (lit : literal) : next =
    match clauses with
    | [] -> Implication (unit_clause, lit)
    | clause :: clauses' ->
      match substitute clause with
      | Some [] -> Conflict clause
      | _ -> search_empty clauses' unit_clause lit
  in
  let rec search_unit (clauses : clause list) : next =
    match clauses with
    | [] -> Decide
    | clause :: clauses' ->
      match substitute clause with
      | Some [] -> Conflict clause
      | Some [lit] -> search_empty clauses' clause lit
      | _ -> search_unit clauses'
  in
  search_unit form

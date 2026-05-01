open Formula
open Utils

type reason =
  | Decision
  | Propagated of clause

type t = 
  { level : int
  ; clauses : Formula.t
  ; learned : Formula.t
  }

type unit_ret =
  | Decide
  | Conflict of clause
  | Implication of clause * literal

let rec analyze_conflict (state : t) (trail : Trail.t list) (conflict : clause) : clause * int =
  match List.filter (fun lit -> Trail.find_level lit trail = state.level) conflict with
  | [hd] ->
    if state.level = 0 then
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
    analyze_conflict state trail conflict'

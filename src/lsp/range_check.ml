open Lang.Ast

let compute_check_index
  (spans : pos_span list)
  (changes : Protocol.range list)
  : int option =
  match spans, changes with
  | [], _ | _, [] -> None
  | _, first_change :: _ ->
    let target = first_change.start_pos in
    List.find_mapi (fun i span ->
      let stmt_end = Positions.of_lexing span.ends in
      if Positions.geq stmt_end target then Some i else None
    ) spans
  (* TODO: Skip spawning the typechecker for non-semantic edits (e.g., inserting blank lines). *)

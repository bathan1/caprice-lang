let compute_check_index
  (spans : Lang.Ast.pos_span list)
  (changes : Protocol.range list)
  : int option =
  match spans, changes with
  | [], _ | _, [] -> None
  | _, first_change :: _ ->
    let target = first_change.start_pos in
    List.find_mapi (fun i span ->
      let stmt_end = Positions.of_lexing span.Lang.Ast.ends in
      if Positions.is_ge stmt_end target then Some i else None
    ) spans
    (* TODO: Skip spawning the typechecker for non-semantic edits (e.g., inserting blank lines). *)
open Lang.Ast

let compute_check_pos
  (stmts_with_pos : program_with_pos)
  (changes : Protocol.range list)
  : pos_span option =
  match stmts_with_pos, changes with
  | [], _ | _, [] -> None
  | _, first_change :: _ ->
    let target = first_change.start_pos in
    List.find_mapi (fun i (_stmt, span) ->
      let stmt_end = Positions.of_lexing span.ends in
      if Positions.geq stmt_end target then
        Some (snd (List.nth stmts_with_pos (max 0 (i - 1))))
      else None
    ) stmts_with_pos
  (* TODO: Skip spawning the typechecker for non-semantic edits (e.g., inserting blank lines). *)

open Lang.Ast

let disable_annot_check (annot : annot) : annot =
  match annot with
  | ANone -> ANone
  | AType r -> AType { r with do_check = false }
  
let disable_stmt_check (stmt : statement) : statement =
  match stmt with
  | SLet r -> SLet { r with annot = disable_annot_check r.annot }
  | SLetRec r -> SLetRec { r with annot = disable_annot_check r.annot }

let disable_all_checks (pgm : program_with_pos) : program_with_pos =
  List.map (fun (stmt, span) -> (disable_stmt_check stmt, span)) pgm

(* On programs with checks enabled, produces programs with exactly one
   check each — the statement at position [start] onward, in turn. *)
let mk_pgms (pgm : program_with_pos) ~start : (pos_span * program) list =
  let rec mk left right =
    match right with
    | [] -> []
    | (stmt, span) :: rem ->
      let res = mk ((disable_stmt_check stmt, span) :: left) rem in
      (span, List.rev_map fst ((stmt, span) :: left)) :: res
  in
  let prev = List.take start (disable_all_checks pgm) in
  mk (List.rev prev) (List.drop start pgm)

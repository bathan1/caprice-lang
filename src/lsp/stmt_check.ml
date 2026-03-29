open Lang.Ast

let disable_annot_check (annot : annot) : annot =
  match annot with
  | ANone -> ANone
  | AType r -> AType { r with do_check = false }
  
let disable_stmt_check (stmt : statement) : statement =
  match stmt with
  | SLet r -> SLet { r with annot = disable_annot_check r.annot }
  | SLetRec r -> SLetRec { r with annot = disable_annot_check r.annot }

let disable_all_checks (stmts : program) : program =
  List.map disable_stmt_check stmts

let mk_pgms pgm ~start =
  let rec mk i left right =
    match right with
    | [] -> []
    | stmt :: rem ->
      let res = mk (i + 1) (disable_stmt_check stmt :: left) rem in
      (i, List.rev (stmt :: left)) :: res
  in
  let prev = List.take start (disable_all_checks pgm) in
  mk start (List.rev prev) (List.drop start pgm)

let pgms_up_to (pgm : program) ~(end_idx : int) : (int * program) list =
  mk_pgms pgm ~start:0
  |> List.take (end_idx + 1)

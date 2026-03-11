open Lang.Ast

let is_stmt_check_enabled (stmt : statement) : bool =
  match stmt with
  | SLet { annot = AType { do_check; tau = _ }; _ }
  | SLetRec { annot = AType { do_check; tau = _ }; _ } -> do_check
  | SLet { annot = ANone; _ }
  | SLetRec { annot = ANone; _ } -> false

let disable_annot_check (annot : annot) : annot =
  match annot with
  | ANone -> ANone
  | AType r -> AType { r with do_check = false }
  
let disable_stmt_check (stmt : statement) : statement =
  match stmt with
  | SLet r -> SLet { r with annot = disable_annot_check r.annot }
  | SLetRec r -> SLetRec { r with annot = disable_annot_check r.annot }

let filter_check_stmt (stmts : program) (target_idx : int) : program =
  if (target_idx < 0 || target_idx >= List.length stmts) then
    failwith (Printf.sprintf "Target index %d is out of bounds" target_idx)
  else
    stmts
    |> List.filteri (fun i _ -> i <= target_idx)
    |> List.mapi (fun i stmt ->
      if i = target_idx then stmt
      else disable_stmt_check stmt
    )

let generate_pgms_list (pgm : program) ~(target_idx : int option) : (int * program) list =
  match target_idx with
  | None -> []
  | Some start_idx ->
    List.init (List.length pgm - start_idx) (fun offset -> start_idx + offset)
    |> (if start_idx > 0 then List.cons (start_idx - 1) else Fun.id)
    |> List.map (fun i -> (i, filter_check_stmt pgm i))

let print_answer ~(spans : Lang.Ast.pos_span list) i answer =
  let span = List.nth spans i in
  let b = Positions.of_lexing span.begins in
  let e = Positions.of_lexing span.ends in
  let pos = Printf.sprintf "%d:%d:%d:%d:%d" i b.line b.character e.line e.character in
  match answer with
  | Grammar.Answer.Found_error msg ->
    Printf.printf "error:%s:%s\n%!" pos msg
  | _ ->
    Printf.printf "ok:%s\n%!" pos
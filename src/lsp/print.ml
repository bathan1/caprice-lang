let span_pos ~(spans : Lang.Ast.pos_span list) i =
  let span = List.nth spans i in
  let b = Positions.of_lexing span.begins in
  let e = Positions.of_lexing span.ends in
  Printf.sprintf "%d:%d:%d:%d:%d" i b.line b.character e.line e.character

let print_pending ~spans i =
  Printf.printf "pending:%s\n%!" (span_pos ~spans i)

let print_answer ~spans i answer =
  let pos = span_pos ~spans i in
  match answer with
  | Grammar.Answer.Found_error msg ->
    Printf.printf "error:%s:%s\n%!" pos msg
  | Grammar.Answer.Timeout _ ->
    Printf.printf "timeout:%s\n%!" pos
  | Grammar.Answer.Unknown ->
    Printf.printf "unknown:%s\n%!" pos
  | Grammar.Answer.Exhausted_pruned ->
    Printf.printf "exhausted_pruned:%s\n%!" pos
  | Grammar.Answer.Exhausted ->
    Printf.printf "ok:%s\n%!" pos

type _ eff += Pause : unit eff

module Pause_effect = struct
  let yield () =
    Effect.perform Pause
end

module M = Concolic.Loop.Make (Pause_effect)

type r =
  | Done of Grammar.Answer.t
  | Cont of (unit, r) Effect.Deep.continuation

type work_item = { span : Lang.Ast.pos_span ; task : unit -> r }

let round_robin (fs : work_item list) : unit =
  let run_q = Queue.of_seq (List.to_seq fs) in
  let enqueue span k =
    let task () = Effect.Deep.continue k () in
    Queue.push { span ; task } run_q
  in
  let rec dequeue () =
    match Queue.take_opt run_q with
    | None -> ()
    | Some { span ; task } ->
      let r =
        try task () with
        | effect Pause, k ->
          Cont k
      in
      match r with
      | Done a ->
        Print.print_answer span a;
        dequeue ()
      | Cont k -> enqueue span k; dequeue ()
  in
  dequeue ()

let ceval_many ~options pgms =
  round_robin (
    List.map (fun (span, pgm) ->
      { span ; task = fun () ->
          Print.print_pending span;
          Done (M.begin_ceval ~print_outcome:false ~options pgm) }
    ) pgms
  )

let find_baseline_error ~options stmts_with_pos =
  let all_disabled = Stmt_check.disable_all_checks stmts_with_pos in
  let baseline =
    Concolic.Loop.begin_ceval ~print_outcome:false ~options (List.map fst all_disabled)
  in
  match baseline with
  | Grammar.Answer.Found_error _ ->
    let rec loop acc = function
      | [] -> None
      | (stmt, span) :: tl ->
        let pgm = acc @ [stmt] in
        match Concolic.Loop.begin_ceval ~print_outcome:false ~options pgm with
        | Grammar.Answer.Exhausted -> loop pgm tl
        | answer -> Some (span, answer)
    in
    loop [] all_disabled
  | _ -> None

let run_typecheck ~(options : Concolic.Options.t) (packet : Protocol.checker_packet) =
  try
    let stmts_with_pos = Lang.Parser.Positioned.parse_string packet.full_text in
    let stmts_to_check =
      match find_baseline_error ~options stmts_with_pos with
      | None -> stmts_with_pos
      | Some (error_span, a) ->
        (* TODO: extend error message to say statements after this are unreachable *)
        let () = Print.print_answer error_span a in
        let rec take = function
          | (_, span) :: _ when span = error_span -> []
          | x :: rest -> x :: take rest
          | [] -> []
        in
        take stmts_with_pos
    in
    let check_index = Range_check.compute_check_index stmts_to_check packet.changes in
    match check_index with
    | None -> ()
    | Some start ->
      stmts_to_check
      |> Stmt_check.mk_pgms ~start
      |> ceval_many ~options
  with
  | Lang.Parser.Parse_error (_exn, line, col, tok) ->
    Printf.printf "parse_error:%d:%d:%s\n%!" line col tok
  | exn ->
    Printf.printf "error:%s\n%!" (Printexc.to_string exn)

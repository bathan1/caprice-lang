
type _ eff += Pause : unit eff

module Pause_effect = struct
  let yield () =
    Effect.perform Pause
end

module M = Concolic.Loop.Make (Pause_effect)

type r =
  | Done of Grammar.Answer.t
  | Cont of (unit, r) Effect.Deep.continuation

type work_item = { id : int ; task : unit -> r }

let round_robin ~spans (fs : work_item list) : unit =
  let run_q = Queue.of_seq (List.to_seq fs) in
  let enqueue id k =
    let task () = Effect.Deep.continue k () in
    Queue.push { id ; task } run_q
  in
  let rec dequeue () =
    match Queue.take_opt run_q with
    | None -> ()
    | Some { id ; task } ->
      let r =
        try task () with
        | effect Pause, k ->
          Cont k
      in
      match r with
      | Done a ->
        Print.print_answer ~spans id a;
        dequeue ()
      | Cont k -> enqueue id k; dequeue ()
  in
  dequeue ()

let ceval_many ~options ~spans pgms =
  round_robin ~spans (
    List.map (fun (id, pgm) ->
      { id ; task = fun () ->
          Print.print_pending ~spans id;
          Done (M.begin_ceval ~print_outcome:false ~options pgm) }
    ) pgms
  )

let find_baseline_error ~options stmts =
  let all_disabled = Stmt_check.disable_all_checks stmts in
  let baseline = Concolic.Loop.begin_ceval ~print_outcome:false ~options all_disabled in
  match baseline with
  | Grammar.Answer.Found_error _ ->
    Stmt_check.mk_pgms all_disabled ~start:0
    |> List.find_map (fun (i, pgm) ->
      match Concolic.Loop.begin_ceval ~print_outcome:false ~options pgm with
      | Grammar.Answer.Exhausted -> None
      | answer -> Some (i, answer))
  | _ -> None

let run_typecheck ~(options : Concolic.Options.t) (packet : Protocol.checker_packet) =
  try
    let stmts_with_pos = Lang.Parser.Positioned.parse_string packet.full_text in
    let stmts = List.map fst stmts_with_pos in
    let spans = List.map snd stmts_with_pos in
    let last_idx = (* last index to check, not inclusive *)
      match find_baseline_error ~options stmts with
      | None -> List.length stmts
      | Some (i, a) -> let () = Print.print_answer ~spans i a in i
    in
    let check_index = Range_check.compute_check_index spans packet.changes in
    match check_index with
    | None -> ()
    | Some start ->
      stmts
      |> List.take last_idx
      |> Stmt_check.mk_pgms ~start
      |> ceval_many ~options ~spans
  with
  | Lang.Parser.Parse_error (_exn, line, col, tok) ->
    Printf.printf "parse_error:%d:%d:%s\n%!" line col tok
  | exn ->
    Printf.printf "error:%s\n%!" (Printexc.to_string exn)

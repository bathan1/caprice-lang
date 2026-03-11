let read_exactly ic n =
  let buf = Bytes.create n in
  really_input ic buf 0 n;
  Bytes.to_string buf

let find_and_print_baseline_error ~options ~spans stmts =
  let all_disabled = Lsp.Stmt_check.disable_all_checks stmts in
  let n = List.length all_disabled in
  let rec loop i =
    if i >= n then
      Printf.printf "error:baseline scan exhausted without finding error\n%!"
    else
      all_disabled
      |> List.filteri (fun j _ -> j <= i)
      |> Concolic.Loop.begin_ceval ~print_outcome:false ~options
      |> (function
          | Grammar.Answer.Exhausted -> loop (i + 1)
          | answer -> Lsp.Print.print_answer ~spans i answer)
  in
  loop 0

let run_typecheck ~(options : Concolic.Options.t) (packet : Lsp.Protocol.checker_packet) =
  try
    let stmts_with_pos = Lang.Parser.Positioned.parse_string packet.full_text in
    let stmts = List.map fst stmts_with_pos in
    let spans = List.map snd stmts_with_pos in
    let check_index = Lsp.Range_check.compute_check_index spans packet.changes in
    let baseline = Concolic.Loop.begin_ceval ~print_outcome:false ~options
      (Lsp.Stmt_check.disable_all_checks stmts)
    in
    match baseline with
    | Grammar.Answer.Found_error _ ->
      find_and_print_baseline_error ~options ~spans stmts
    | _ ->
      stmts
      |> Lsp.Stmt_check.generate_pgms_list ~target_idx:check_index
      |> Concolic.Loop.ceval_many ~options ~spans
  with
  | Lang.Parser.Parse_error (_exn, line, col, tok) ->
    Printf.printf "parse_error:%d:%d:%s\n%!" line col tok
  | exn ->
    Printf.printf "error:%s\n%!" (Printexc.to_string exn)

let process_one_change ~(options : Concolic.Options.t) =
  let packet_text =
    stdin
    |> input_line
    |> int_of_string
    |> read_exactly stdin
  in
  match Lsp.Protocol.parse_checker_packet packet_text with
  | Ok packet -> run_typecheck ~options packet
  | Error msg -> Printf.printf "protocol_error:%s\n%!" msg;
  Printf.printf "done\n%!"

let rec server_loop ~(options : Concolic.Options.t) () =
  try
    process_one_change ~options;
    server_loop ~options ()
  with
  | End_of_file -> ()

let typecheck_lsp_main =
  Cmdliner.Cmd.v (Cmdliner.Cmd.info "typecheck_lsp") @@
  let open Cmdliner.Term.Syntax in
  let+ options = Concolic.Options.of_argv in
  server_loop ~options ()

let () = 
  match Cmdliner.Cmd.eval_value' typecheck_lsp_main with
  | `Ok _ -> ()
  | `Exit i -> exit i

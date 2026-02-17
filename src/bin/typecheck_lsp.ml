let read_exactly ic n =
  let buf = Bytes.create n in
  really_input ic buf 0 n;
  Bytes.to_string buf

let process_one_change ~(options : Concolic.Options.t) =
  let byte_len = int_of_string (input_line stdin) in
  let source_text = read_exactly stdin byte_len in
  try
    Lang.Parser.parse_string source_text
    |> Concolic.Loop.begin_ceval ~print_outcome:false ~options
    |> Grammar.Answer.to_string
    |> Printf.printf "ok:%s\n%!"
  with
  | Lang.Parser.Parse_error (_exn, line, col, tok) ->
    Printf.printf "parse_error:%d:%d:%s\n%!" line col tok
  | exn ->
    Printf.printf "error:%s\n%!" (Printexc.to_string exn)

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

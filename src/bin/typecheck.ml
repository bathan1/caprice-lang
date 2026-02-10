
let typecheck_main =
  Cmdliner.Cmd.v (Cmdliner.Cmd.info "typecheck") @@
  let open Cmdliner.Term.Syntax in
  let+ caprice_pgm = Lang.Parser.parse_program_from_argv
  and+ options = Concolic.Options.of_argv in
  let filtered_pgm = Lang.Ast.Tools.filter_check_stmt caprice_pgm options.check_index in
  Concolic.Loop.begin_ceval ~options filtered_pgm

let () = 
  match Cmdliner.Cmd.eval_value' typecheck_main with
  | `Ok _ -> ()
  | `Exit i -> exit i

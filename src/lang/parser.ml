open Lexing

exception Parse_error of exn * int * int * string

module Base = struct
  let handle_parse_error buf f =
    try f ()
    with exn ->
      let curr = buf.lex_curr_p in
      let line = curr.pos_lnum in
      let column = curr.pos_cnum - curr.pos_bol in
      let tok = lexeme buf in
      raise @@ Parse_error (exn, line, column, tok)
  
  let parse_program entry_point (input : in_channel) =
    let buf = Lexing.from_channel input in
    handle_parse_error buf @@ fun () ->
    entry_point Caprice_lexer.token buf
  
  let parse_file parser (filename : string) =
    In_channel.with_open_bin filename parser
  
  let parse_program_from_argv file_parser =
    let open Cmdliner.Term.Syntax in
    let+ src_file = 
      let open Cmdliner.Arg in
      required & pos 0 (some' file) None & info [] ~docv:"FILE" ~doc:"Input filename"
    in
    file_parser src_file
end

module Plain = struct
  let parse_program input : Ast.statement list = Base.parse_program Caprice_parser.prog input

  let parse_file filename : Ast.statement list = Base.parse_file parse_program filename

  let parse_program_from_argv = Base.parse_program_from_argv parse_file
end

module Positioned = struct
  let parse_program input : Ast.statement_with_pos list = Base.parse_program Caprice_parser.prog_with_pos input

  let parse_file filename : Ast.statement_with_pos list = Base.parse_file parse_program filename

  let parse_program_from_argv = Base.parse_program_from_argv parse_file
end

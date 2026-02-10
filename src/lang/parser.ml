open Lexing

exception Parse_error of exn * int * int * string

module type PARSER_ENTRY = sig
  type result
  val entry_point : (Lexing.lexbuf -> Caprice_parser.token) -> Lexing.lexbuf -> result
end

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

module Make(E: PARSER_ENTRY) = struct
  let parse_program (input : in_channel) : E.result = Base.parse_program E.entry_point input
  let parse_file (filename : string) : E.result = Base.parse_file parse_program filename
  let parse_program_from_argv = Base.parse_program_from_argv parse_file
end

module Plain = Make (struct
  type result = Ast.statement list
  let entry_point = Caprice_parser.prog
end)

module Positioned = Make (struct
  type result = Ast.statement_with_pos list
  let entry_point = Caprice_parser.prog_with_pos
end)

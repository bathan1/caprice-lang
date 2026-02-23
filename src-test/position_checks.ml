let parse_position (piece : string) : ((int * int) * (int * int)) =
  Scanf.sscanf piece "%d:%d-%d:%d"
    (fun a b c d -> ((a, b), (c, d)))

let parse_positions (s : string) : ((int * int) * (int * int)) list =
  s
  |> String.split_on_char ','
  |> List.map String.trim
  |> List.map parse_position

let parse_int_list (s : string) : int list =
  s
  |> String.split_on_char ','
  |> List.map String.trim
  |> List.map int_of_string

let mk_range (((sl, sc), (el, ec)) : ((int * int) * (int * int))) : Lsp.Protocol.range =
  {
    start_pos = { line = sl; character = sc };
    end_pos = { line = el; character = ec };
  }

let parse_changes (s : string) : Lsp.Protocol.range list =
  s
  |> parse_positions
  |> List.map mk_range

let parse_spans_from_file (filename : string) : Lang.Ast.pos_span list =
  filename
  |> Lang.Parser.Positioned.parse_file
  |> List.map snd

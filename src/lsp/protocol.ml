open Positions

type range = { start_pos : pos ; end_pos : pos }

type checker_packet =
  { uri : string
  ; version : int
  ; full_text : string
  ; changes : range list
  }

let parse_position json : pos =
  let open Yojson.Safe.Util in
  { line = json |> member "line" |> to_int
  ; character = json |> member "character" |> to_int
  }

let parse_range json =
  let open Yojson.Safe.Util in
  { start_pos = json |> member "start" |> parse_position
  ; end_pos = json |> member "end" |> parse_position
  }

let parse_checker_packet packet_text =
  try
    let json = Yojson.Safe.from_string packet_text in
    let open Yojson.Safe.Util in
    Ok
      { uri = json |> member "uri" |> to_string
      ; version = json |> member "version" |> to_int
      ; full_text = json |> member "fullText" |> to_string
      ; changes = json |> member "changes" |> to_list |> List.map parse_range
      }
  with
  | Yojson.Json_error msg ->
    Error ("invalid_json:" ^ msg)
  | Yojson.Safe.Util.Type_error (msg, _json) ->
    Error ("bad_packet:" ^ msg)

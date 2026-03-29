type pos = { line : int ; character : int }

let of_lexing (p : Lexing.position) : pos =
  { line = p.pos_lnum - 1
  ; character = p.pos_cnum - p.pos_bol
  }

let of_1based (line : int) (col : int) : pos =
  { line = line - 1 ; character = col - 1 }

let compare (a : pos) (b : pos) : int =
  match Int.compare a.line b.line with
  | 0 -> Int.compare a.character b.character
  | cmp -> cmp

let geq (a : pos) (b : pos) : bool =
  compare a b >= 0
type pos = {
  line : int;
  character : int;
}

let of_lexing (p : Lexing.position) : pos =
  {
    line = p.pos_lnum - 1;
    character = p.pos_cnum - p.pos_bol;
  }

let compare (a : pos) (b : pos) : int =
  match Int.compare a.line b.line with
  | 0 -> Int.compare a.character b.character
  | cmp -> cmp

let is_ge (a : pos) (b : pos) : bool =
  compare a b >= 0
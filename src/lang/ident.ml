
module T = struct
  type t = Ident of string [@@unboxed]

  let compare (Ident a) (Ident b) =
    String.compare a b
    
  let equal (Ident a) (Ident b) =
    String.equal a b
end

include T

let to_string (Ident s) = s

module Map = Baby.W.Map.Make (T)


module T = struct
  type t = Uid of int [@@unboxed]

  let compare (Uid a) (Uid b) =
    Int.compare a b

  let equal (Uid a) (Uid b) =
    Int.equal a b
end

include T

let[@inline always] of_int i = Uid i
let[@inline always] to_int (Uid i) = i

let counter = Counter.create ()

let make_new () = Uid (Counter.next counter)

module Map = Baby.W.Map.Make (T)
module Set = Baby.W.Set.Make (T)

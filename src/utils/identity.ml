
type 'a t = 'a

let compare : ('a -> 'a -> int) -> ('a t -> 'a t -> int) = Fun.id
let equal : ('a -> 'a -> bool) -> ('a t -> 'a t -> bool) = Fun.id

let to_string f a = f a

module Monad = struct
  type 'a m = 'a t
  let[@inline] bind x f = f x
  let[@inline] return x = x
end

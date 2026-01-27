
type t = int Atomic.t

let create () : t =
  Atomic.make 0

let next (x : t) : int =
  let () = Atomic.incr x in
  Atomic.get x

let get (x : t) : int =
  Atomic.get x

let reset (x : t) : unit =
  Atomic.set x 0

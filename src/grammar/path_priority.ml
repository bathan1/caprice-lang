
type t = Priority of int [@@unboxed]

let compare (Priority a) (Priority b) = Int.compare a b

let zero = Priority 0

let one = Priority 1

let geq (Priority n1) (Priority n2) = n1 >= n2

let[@inline] plus (Priority a) (Priority b) =
  Priority (a + b)

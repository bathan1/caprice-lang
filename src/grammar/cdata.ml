
(* concolic data *)
type 'a t = 'a * 'a Formula.t

let to_string f (a, _) = f a

let true_ : bool t = true, Formula.const_bool true
let false_ : bool t = false, Formula.const_bool false

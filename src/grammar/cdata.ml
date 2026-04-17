
(* concolic data *)
type 'a t = 'a * 'a Formula.t

let to_string f (a, _) = f a

let of_bool b = b, Formula.const_bool b

let true_ : bool t = of_bool true
let false_ : bool t = of_bool false

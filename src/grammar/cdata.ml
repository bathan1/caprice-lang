
(* concolic data *)
type 'a t = 'a * 'a Formula.t

let to_string f (a, _) = f a

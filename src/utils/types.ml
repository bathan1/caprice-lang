
module type T = sig
  type t
end

module type T1 = sig
  type 'a t
end

(* Printable with one type parameter *)
module type P1 = sig
  include T1
  val to_string : ('a -> string) -> 'a t -> string
end

module type MONAD = sig
  type 'a m
  val return : 'a -> 'a m
  val bind : 'a m -> ('a -> 'b m) -> 'b m
end

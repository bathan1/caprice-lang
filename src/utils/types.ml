
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

module type INDEXED_MONAD = sig
  type ('a, 'i) m
  val return : 'a -> ('a, 'i) m
  val bind : ('a, 'i) m -> ('a -> ('b, 'i) m) -> ('b, 'i) m
end

module type MONAD = sig
  type 'a m
  include INDEXED_MONAD with type ('a, 'i) m := 'a m
end

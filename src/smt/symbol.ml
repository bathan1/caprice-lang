
module type KEY = sig
  type t
  val uid : t -> Utils.Uid.t
end

module Make_comparable_key (K : KEY) = struct
  include K
  let compare a b = Utils.Uid.compare (uid a) (uid b)
  let equal a b = Utils.Uid.equal (uid a) (uid b)
end

(* Symbols have a phantom 'k (key) parameter. The underlying
  key is actually a Uid.t *)
type ('a, 'k) t = ('a, Utils.Uid.t) s
and (_, 'b) s =
  | I : 'b -> (int, 'b) s
  | B : 'b -> (bool, 'b) s

let compare (type a) (x : (a, 'k) t) (y : (a, 'k) t) : int =
  match x, y with
  | I xi, I yi
  | B xi, B yi -> Utils.Uid.compare xi yi

let equal (type a) (x : (a, 'k) t) (y : (a, 'k) t) : bool =
  match x, y with
  | I xi, I yi
  | B xi, B yi -> Utils.Uid.equal xi yi

let make_int (k : 'k) (uid : 'k -> Utils.Uid.t) : (int, 'k) t =
  I (uid k)

let make_bool (k : 'k) (uid : 'k -> Utils.Uid.t) : (bool, 'k) t =
  B (uid k)

module Make (Key : KEY) = struct
  type nonrec 'a t = ('a, Key.t) t

  let make_int (k : Key.t) : int t =
    make_int k Key.uid

  let make_bool (k : Key.t) : bool t =
    make_bool k Key.uid
end

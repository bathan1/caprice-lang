
(* Identifier for a suspended value. *)
module T = struct
  type 'a t = { id : int } [@@unboxed]
    [@@deriving eq, ord]
end

include T

module Map : sig
  type 'a t
  val empty : 'a t
  val add : 'a T.t -> 'a -> 'a t -> 'a t
  val find : 'a T.t -> 'a t -> 'a option
  val find_exn : 'a T.t -> 'a t -> 'a
end = struct
  module IntMap = Baby.W.Map.Make (Int)
  type 'a t = 'a IntMap.t

  let empty : 'a t = IntMap.empty

  let add ({ id } : 'a T.t) (v : 'a) (m : 'a t) : 'a t =
    IntMap.add id v m

  let find ({ id } : 'a T.t) (m : 'a t) : 'a option =
    IntMap.find_opt id m

  let find_exn ({ id } : 'a T.t) (m : 'a t) : 'a =
    IntMap.find id m
end

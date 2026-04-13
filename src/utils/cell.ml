
(* keys to identify typed cells *)
module T = struct
  type 'a t = 'a Type.Id.t
end

include T

(** [new_cell ()] is a guaranteed new typed identifier. Under the hood,
  a variant is extended, so this costs roughly as much as incrementing
  a counter. The benefit is that we can avoid magic for the heterogenous
  map. *)
let new_cell () = Type.Id.make ()

let equal c1 c2 = Type.Id.uid c1 = Type.Id.uid c2

let id c = Type.Id.uid c

(* Heterogenous map from cells to values in those cells *)
module Map = struct
  type binding = Binding : 'a t * 'a -> binding

  module M = Baby.W.Map.Make (Int)

  type t = binding M.t

  let empty = M.empty

  let add k v m =
    M.add (Type.Id.uid k) (Binding (k, v)) m

  let find : type a. a T.t -> t -> a = fun k m ->
    match M.find (Type.Id.uid k) m with
    | Binding (k', v) ->
      match Type.Id.provably_equal k k' with
      | Some Type.Equal -> v
      | None -> assert false
end

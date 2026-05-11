(** (from, to, weight) *)
type 'node edge = 'node * 'node * int

(** [bellman_ford ~src edges] runs Bellman Ford to find the min distances
    from SRC node to all other nodes in EDGES and returns either...

    1. [`No_negative_cycle distance] when no cycle was detected, where
       [distance.(x)] is the min distance from SRC to [x] for each [0 <= x < num_nodes]

    2. [`Negative_cycle indices] when a negative cycle was found, where INDICES
       is the index {b list} [[ i0 ; i1 ; ... ; im ]] of the edges that compose
       the cycle.
*)
val bellman_ford :
  (module Baby.OrderedType with type t = 'node) ->
  src:'node ->
  'node edge list ->
  [ `No_negative_cycle of ('node * int) list
  | `Negative_cycle of 'node edge list
  ]

module Make (Node : Baby.OrderedType) : sig
  (** (from, to, weight) *)
  type edge = Node.t * Node.t * int

  (** A predecessor records the edge used to reach a node, plus the previous tail node. *)
  type pred

  (** Represents the distance/predecessor tracking state. *)
  type paths =
    distance:(Node.t, int) Hashtbl.t
    * predecessor:(Node.t, pred) Hashtbl.t

  type loop = {
    paths : paths;
    is_updated : bool;
  }

  val relax_distance : loop -> edge -> loop

  val relax_distances :
    int ->
    edge list ->
    loop ->
    int ->
    [ `Continue of loop
    | `Stop of paths
    ]

  val find_paths : src:Node.t -> int -> edge list -> paths

  val find_cycle_edge :
    (Node.t, int) Hashtbl.t ->
    edge list ->
    (pred * Node.t) option
end

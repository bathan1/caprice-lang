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
  type key = Node.t
  type value = int * Node.t edge option
  type tbl = (key, value) Hashtbl.t
  type t = tbl * int

  val count : Node.t edge list -> int

  val create_tbl : src:Node.t -> Node.t edge list -> t

  val relax_distance : bool -> Node.t edge -> tbl -> bool

  val relax_distances : Node.t edge list -> tbl -> bool

  val relax : Node.t edge list -> t -> int ->
    [ `Continue of t | `Stop of tbl ]

  val find_distances : src:Node.t -> Node.t edge list -> t

  val find_cycle_edge_opt : Node.t edge list -> tbl -> Node.t edge option

  val find_predecessor_opt : Node.t -> tbl -> Node.t option

  val find_cycle_start : Node.t -> t -> Node.t
end

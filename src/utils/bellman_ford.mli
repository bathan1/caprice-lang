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

(** [Make Node] instantiates the Bellman Ford operations module. *)
module Make (Node : Baby.OrderedType) : sig
  (** Hashtbl key by [Node.t] indexes our current distance state to KEY node. *)
  type key = Node.t

  (** [(distance, predecessor_edge)] means for some key-ed node, our minimum DISTANCE path to that 
      node from our source ends with edge PREDECESSOR_EDGE. We use options on both to represent infinity
      and the null parent respectively.
  *)
  type value = int option * Node.t edge option

  (** So we don't have to type out the full type each time... *)
  type tbl = (key, value) Hashtbl.t

  (** [create_tbl ~src edges] returns the initial distance table state for a bellman ford run from
      SRC to all other nodes in EDGES
  *)
  val create_tbl : src:Node.t -> Node.t edge list -> tbl

  val relax_edge : tbl -> bool -> Node.t edge -> bool
  
  val relax_edges : Node.t edge list -> tbl -> int ->
    [ `Continue of tbl | `Stop of tbl ]

  val find_distances : src:Node.t -> Node.t edge list -> tbl

  (** [find_relaxed_node_opt edges tbl] finds the first node from EDGES that is part of the
      negative cycle *and* applies the relaxation to [to_], if it exists in tbl from DIST
      otherwise it throws
  *)
  val find_relaxed_node_opt : Node.t edge list -> tbl -> Node.t option
  
  (** [find_relaxed_node edges tbl] finds the [to_] node of the first edge from EDGES that is part of the negative cycle *and* applies the relaxation to [to_], if it exists in tbl from DIST otherwise it throws *)
  val find_relaxed_node : Node.t edge list -> tbl -> Node.t

  val find_cycle_entry_opt : Node.t edge list -> tbl -> Node.t option

  val find_cycle_entry : Node.t edge list -> tbl -> Node.t

  val find_predecessor_edge : Node.t -> tbl -> Node.t edge option

  val find_predecessor : Node.t -> tbl -> Node.t option

  val collect_cycle : Node.t -> tbl -> Node.t edge list
end

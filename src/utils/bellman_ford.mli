(** (from, to, weight) *)
type 'a edge = 'a * 'a * int

(** A pred { index ; tail } represents the tail NODE that directs edge at INDEX
    to the index of the predecessor array *)
type pred

(** Represents the distance tracking state *)
type paths = distance:int option array * predecessor:pred option array

(** The [is_updated] flag lets us early exit if the distances
    didn't change for any iteration of the relax proc *)
type loop = { paths : paths ; is_updated : bool }

(** [relax_distance loop i edge] computes the next [LOOP.path=(DISTANCE, PREDECESSOR)]
    state for FROM node at the I-th indexed [EDGE=(FROM, TO, WEIGHT)], lowering
    the distance for TO when the [DISTANCE.(FROM) + WEIGHT] is less than the
    distance at [DISTANCE.(TO)]

    We use a [loop] record instead of [path] to encode the state so
    we can early-exit when distances haven't been updated with the bool flag.
*)
val relax_distance : loop -> int edge -> loop

(** [relax_distances nodes edges loop i] is the I-th iteration of finding
    the next [loop] state from the [I - 1] LOOP state and returns [`Continue]
    if at least 1 distance was lowered in [relax_distance], otherwise early exiting
    with [`Stop] *)
val relax_distances : int -> int edge list -> loop -> int ->
  [ `Continue of loop
  | `Stop of paths
  ]

(** [find_paths ~src nodes edges] finds the minimum distance from SRC to
    all other NODES in EDGES *)
val find_paths : src:int -> int -> int edge list -> paths

(** [find_cycle_edge distance edges] returns the first [(index, tail)]
    tuple encoding an edge from [EDGES.(INDEX)] with [from = TAIL]
    whose negative weight further drops DISTANCE's path distances *)
val find_cycle_edge : int option array -> int edge list -> (pred * int) option

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

type 'node edge = 'node * 'node * int

type 'node pred = { edge : 'node edge ; tail : 'node }

type 'node paths = distance:('node, int) Hashtbl.t * predecessor:('node, 'node pred) Hashtbl.t

type 'node loop = { paths : 'node paths ; is_updated : bool }

let relax_distance
  (state : 'node loop)
  (edge : 'node edge)
  : 'node loop =
  let { paths = ~distance, ~predecessor ; _ } = state in
  let from_, to_, weight = edge in
  match Hashtbl.find_opt distance from_, Hashtbl.find_opt distance to_ with
  | Some du, None ->
    Hashtbl.replace distance to_ (du + weight);
    Hashtbl.replace predecessor to_ { edge ; tail = from_ };
    { paths = (~distance, ~predecessor) ; is_updated = true }

  | Some du, Some dv when du + weight < dv ->
    Hashtbl.replace distance to_ (du + weight);
    Hashtbl.replace predecessor to_ { edge ; tail = from_ };
    { paths = ~distance, ~predecessor ; is_updated = true }

  | _ -> state

let relax_distances (num_nodes : int) (edges : 'node edge list) (state : 'node loop) (i : int)
  : [ `Continue of 'node loop
    | `Stop of 'node paths
    ] =
  let { paths ; is_updated } = state in
  if i = num_nodes - 1 then `Stop paths
  else
    let iter =
      List.fold_left relax_distance { paths ; is_updated } edges
    in
    if iter.is_updated then `Continue iter
    else `Stop paths

let init_distance (src : 'node) (num_nodes : int) =
  let distance = Hashtbl.create num_nodes in
  Hashtbl.add distance src 0;
  distance

let find_paths ~(src : 'node) (nodes : int) (edges : 'node edge list) =
  let distance = init_distance src nodes in
  let predecessor = Hashtbl.create nodes in
  let vertices = Array.init nodes Fun.id in
  Array_utils.fold_until
    (relax_distances nodes edges)
    (fun { paths ; _ } -> paths)
    { paths = ~distance, ~predecessor ; is_updated = false }
    vertices

let find_cycle_edge (distance : ('node, int) Hashtbl.t) (edges : 'node edge list) =
  List.find_map
    (fun ((from_, to_, weight) as edge) ->
      match Hashtbl.find_opt distance from_, Hashtbl.find_opt distance to_ with
      | Some du, Some dv when du + weight < dv ->
        Some ({ edge ; tail = from_ }, to_)
      | _ -> None)
    edges

let find_paths_or_cycle ~(src : 'node) (num_nodes : int) (edges : 'node edge list) =
  let ~distance, ~predecessor = find_paths ~src num_nodes edges in
  let cycle_edge = find_cycle_edge distance edges in
  match cycle_edge with
  | None -> `No_negative_cycle distance
  | Some ({ edge ; tail = cycle_tail }, cycle_start) ->
  (* This edge proves a negative cycle, so include it in the predecessor graph. *)
    Hashtbl.replace predecessor cycle_start { edge ; tail = cycle_tail } ;

    let rec move_back vertex n =
      if n = 0 then vertex
      else
        match Hashtbl.find_opt predecessor vertex with
        | None -> vertex
        | Some { tail ; _ } -> move_back tail (n - 1)
    in

  let start = move_back cycle_tail num_nodes in

  let rec collect curr seen acc =
    if List.mem curr seen then acc
    else
      match Hashtbl.find_opt predecessor curr with
      | None -> acc
      | Some { edge ; tail } ->
        collect tail (curr :: seen) (edge :: acc)
  in

  `Negative_cycle (collect start [] [])

let bellman_ford
  (type node)
  (module Node : Baby.OrderedType with type t = node)
  ~(src : node)
  (edges : node edge list)
  : [ `No_negative_cycle of (node * int) list
    | `Negative_cycle of node edge list
    ] =
  let module NodeIterables = Set_map.Make_W (Node) in
  let module NodeSet = NodeIterables.Set in

  let nodes =
    edges
    |> List.fold_left
         (fun acc (from_, to_, _) ->
           acc
           |> NodeSet.add from_
           |> NodeSet.add to_)
         (NodeSet.singleton src)
    |> NodeSet.cardinal
  in

  match find_paths_or_cycle ~src nodes edges with
  | `No_negative_cycle distances ->
    `No_negative_cycle (List.of_seq @@ Hashtbl.to_seq distances)
  | `Negative_cycle cycle_edges -> `Negative_cycle cycle_edges


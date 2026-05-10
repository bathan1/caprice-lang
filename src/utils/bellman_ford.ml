type 'a edge = 'a * 'a * int

type pred = { edge : int edge ; tail : int }

type min_paths = distance:int option array * predecessor:pred option array

type loop = { paths : min_paths ; is_updated : bool }

let relax_distance
  (state : loop)
  (edge : int edge)
  : loop =
  let { paths = ~distance, ~predecessor ; _ } = state in
  let from_, to_, weight = edge in
  match distance.(from_), distance.(to_) with
  | Some du, None ->
    distance.(to_) <- Some (du + weight);
    predecessor.(to_) <- Some { edge ; tail = from_ };
    { paths = (~distance, ~predecessor) ; is_updated = true }

  | Some du, Some dv when du + weight < dv ->
    distance.(to_) <- Some (du + weight);
    predecessor.(to_) <- Some { edge ; tail = from_ };
    { paths = ~distance, ~predecessor ; is_updated = true }

  | _ -> state

let relax_distances nodes edges
  ({ paths ; is_updated } : loop)
  (i : int)
  : [ `Continue of loop
    | `Stop of min_paths
    ] =
  if i = nodes - 1 then `Stop paths
  else
    let iter =
      List.fold_left relax_distance { paths ; is_updated } edges
    in
    if iter.is_updated then `Continue iter
    else `Stop paths

let find_min_paths ~(src : int) (nodes : int) (edges : int edge list) =
  let distance = Array.init nodes (fun i -> if i = src then Some 0 else None) in
  let predecessor : pred option array = Array.init nodes (fun _ -> None) in
  let vertices = Array.init nodes Fun.id in
  Array_utils.fold_until
    (relax_distances nodes edges)
    (fun { paths ; _ } -> paths)
    { paths = ~distance, ~predecessor ; is_updated = false }
    vertices

let find_cycle_edge distance edges =
  List.find_map
    (fun ((from_, to_, weight) as edge) ->
      match distance.(from_), distance.(to_) with
      | Some du, Some dv when du + weight < dv ->
        Some ({ edge ; tail = from_ }, to_)
      | _ -> None)
    edges

let bellman_ford_proc ~(src : int) (edges : int edge list) =
  let nodes =
    edges
    |> List.fold_left (fun acc (u, v, _) ->
      acc
      |> Iterables.IntSet.add u
      |> Iterables.IntSet.add v
    ) Iterables.IntSet.empty
    |> Iterables.IntSet.cardinal
  in
  let ~distance, ~predecessor = find_min_paths ~src nodes edges in
  let cycle_edge = find_cycle_edge distance edges in
  match cycle_edge with
  | None ->
    let distance_map =
      distance
      |> Array.mapi (fun i dist -> i, Option.value ~default:Int.max_int dist)
      |> Iterables.IntMap.of_array
    in
    `No_negative_cycle distance_map
  | Some ({ edge ; tail = cycle_tail }, cycle_start) ->
  (* This edge proves a negative cycle, so include it in the predecessor graph. *)
  predecessor.(cycle_start) <- Some { edge ; tail = cycle_tail };

  let rec move_back vertex n =
    if n = 0 then vertex
    else
      match predecessor.(vertex) with
      | None -> vertex
      | Some { tail ; _ } -> move_back tail (n - 1)
  in

  let start = move_back cycle_tail nodes in

  let rec collect curr seen acc =
    if List.mem curr seen then acc
    else
      match predecessor.(curr) with
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
  let module NodeMap = NodeIterables.Map in
  let module NodeSet = NodeIterables.Set in

  let nodes =
    edges
    |> List.fold_left
         (fun acc (from_, to_, _) ->
           acc
           |> NodeSet.add from_
           |> NodeSet.add to_)
         (NodeSet.singleton src)
  in

  let node_to_index =
    nodes
    |> NodeSet.to_seq
    |> Seq.fold_left
         (fun (i, map) node ->
           i + 1, NodeMap.add node i map)
         (0, NodeMap.empty)
    |> snd
  in

  let index_to_node =
    NodeMap.fold
      (fun node index acc -> Iterables.IntMap.add index node acc)
      node_to_index
      Iterables.IntMap.empty
  in

  let get_index node =
    NodeMap.find node node_to_index
  in

  let indexed_edges =
    edges
    |> List.map (fun (from_, to_, weight) ->
      get_index from_, get_index to_, weight)
  in

  let src_i = get_index src in

  match bellman_ford_proc ~src:src_i indexed_edges with
  | `No_negative_cycle distances ->
    let distances' =
      Iterables.IntMap.fold
        (fun index distance acc ->
          let node = Iterables.IntMap.find index index_to_node in
          (node, distance) :: acc)
        distances
        []
    in
    `No_negative_cycle distances'
  | `Negative_cycle cycle_edges ->
    let cycle_edges' =
      cycle_edges
      |> List.map (fun (from_i, to_i, weight) ->
        let from_ = Iterables.IntMap.find from_i index_to_node in
        let to_ = Iterables.IntMap.find to_i index_to_node in
        from_, to_, weight)
    in
    `Negative_cycle cycle_edges'


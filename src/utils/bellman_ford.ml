type 'node edge = 'node * 'node * int

module Make (Node : Baby.OrderedType) = struct
  type key = Node.t

  type value = int * Node.t edge option
  (** 2-tuple (distance, predecessor) has current shortest DISTANCE
      with the corresponding PREDECESSOR edge to some node key *)

  type tbl = (key, value) Hashtbl.t
  type t = tbl * int

  let count (edges : Node.t edge list) : int =
    let module NodeSet = Set.Make (Node) in
    let node_set = List.fold_left (fun acc (from_, to_, _) ->
      acc
      |> NodeSet.add from_
      |> NodeSet.add to_
    ) NodeSet.empty edges
    in
    NodeSet.cardinal node_set

  let create_tbl ~(src : Node.t) (edges : Node.t edge list) : t =
    let n = count edges in
    let tbl = Hashtbl.create n in
    let () =
      Hashtbl.add tbl src (0, None)
    in
    tbl, n

  let relax_distance (last_updated : bool) (edge : Node.t edge) (tbl : tbl) : bool =
    let from_, to_, cost = edge in
    match Hashtbl.find_opt tbl from_, Hashtbl.find_opt tbl to_ with
    | Some (du, _), None ->
      Hashtbl.replace tbl to_ (du + cost, Some edge);
      last_updated || true
    | Some (du, _), Some (dv, _) when du + cost < dv ->
      Hashtbl.replace tbl to_ (du + cost, Some edge);
      last_updated || true
    | _ -> last_updated || false

  let relax_distances (edges : Node.t edge list) (tbl : tbl) : bool =
    List.fold_left
      (fun is_updated edge -> relax_distance is_updated edge tbl)
      false edges

  let relax (edges : Node.t edge list) (tbl, num_nodes : t) (i : int)
    : [ `Continue of t | `Stop of tbl ] =
    if i = num_nodes - 1 then `Stop tbl
    else if relax_distances edges tbl then `Continue (tbl, num_nodes)
    else `Stop tbl

  let find_distances ~(src : Node.t) (edges : Node.t edge list) =
    let tbl, num_nodes = create_tbl ~src edges in
    let vertices = List.init num_nodes Fun.id in
    let final_tbl = List_utils.fold_left_until
      (fun t i -> relax edges t i)
      fst
      (tbl, num_nodes)
      vertices
    in
    final_tbl, num_nodes

  let find_predecessor_edge (node : Node.t) (tbl : tbl)
    : Node.t edge option =
    snd @@ Hashtbl.find tbl node

  let find_predecessor (node : Node.t) (tbl : tbl) : Node.t option =
    Option.map (fun (from_, _, _) -> from_) (find_predecessor_edge node tbl)
    
  let find_relaxed_node_opt (edges : Node.t edge list) (tbl : tbl) : Node.t option =
    List.find_map (fun ((_, to_, _) as edge) ->
      if relax_distance false edge tbl then
        Some to_
      else None)
    edges

  let find_relaxed_node (edges : Node.t edge list) (tbl : tbl) : Node.t =
    match find_relaxed_node_opt edges tbl with
    | Some node -> node
    | None -> failwith "No relaxed node found"

  let find_cycle_entry_opt (edges : Node.t edge list) (tbl, num_nodes : t)
    : Node.t option =
    let relaxed_predecessor = find_relaxed_node_opt edges tbl in
    match relaxed_predecessor with
    | None -> None
    | Some entry ->
      let rec move_back node n =
        if n = 0 then node
        else if n < num_nodes && node = entry then node
        else
          match find_predecessor node tbl with
          | None -> node
          | Some from_ -> move_back from_ (n - 1)
      in
      Some (move_back entry num_nodes)
      
  let find_cycle_entry (edges : Node.t edge list) (t : t) : Node.t =
    match find_cycle_entry_opt edges t with
    | Some entry -> entry
    | None -> failwith "No negative cycle found"

  let collect_cycle (start : Node.t) (tbl, num_nodes : t) : Node.t edge list =
    let rec loop curr n acc =
      if n = 0 then
        acc
      else
        match find_predecessor_edge curr tbl with
        | None -> acc
        | Some ((from_, _, _) as pred_edge) ->
          let acc = pred_edge :: acc in
          if Node.compare from_ start = 0 then acc
          else loop from_ (n - 1) acc
    in
    loop start num_nodes []
end

let bellman_ford
  (type node)
  (module Node : Baby.OrderedType with type t = node)
 ~(src : node)
  (edges : node edge list)
  : [ `No_negative_cycle of (node * int) list
    | `Negative_cycle of node edge list
    ] =
  let open Make (Node) in
  let tbl, num_nodes = find_distances ~src edges in
  match find_cycle_entry_opt edges (tbl, num_nodes) with
  | None -> `No_negative_cycle (
    tbl
    |> Hashtbl.to_seq
    |> Seq.map (fun (node, (dist, _)) -> node, dist)
    |> List.of_seq
  )
  | Some entry -> `Negative_cycle (collect_cycle entry (tbl, num_nodes))

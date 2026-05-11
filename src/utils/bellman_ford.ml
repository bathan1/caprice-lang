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

  let find_cycle_entry_opt (edges : Node.t edge list) (tbl : tbl)
    : Node.t option =
    List.find_map
      (fun ((from_, to_, weight) as edge) ->
        match Hashtbl.find_opt tbl from_, Hashtbl.find_opt tbl to_ with
        | Some (du, _), Some (dv, _) when du + weight < dv ->
          ignore (relax_distance true edge tbl);
          Some to_
        | _ -> None)
      edges

  let find_cycle (start : Node.t) (tbl, num_nodes : t) : Node.t =
    let rec move_back node n =
      if n = 0 then node
      else
        match find_predecessor node tbl with
        | None -> node
        | Some from_ -> move_back from_ (n - 1)
    in
    move_back start num_nodes
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
  match find_cycle_entry_opt edges tbl with
  | None -> `No_negative_cycle (
    tbl
    |> Hashtbl.to_seq
    |> Seq.map (fun (node, (dist, _)) -> node, dist)
    |> List.of_seq
  )
  | Some end_ ->
    let start = find_cycle end_ (tbl, num_nodes) in
    let rec collect curr n acc =
      if n = 0 then acc
      else
        match find_predecessor_edge curr tbl with
        | None -> acc
        | Some ((from_, _, _) as pred_edge) ->
            collect from_ (n - 1) (pred_edge :: acc)
    in
    `Negative_cycle (collect start num_nodes [])

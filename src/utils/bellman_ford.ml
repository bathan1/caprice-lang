type edge = int * int * int

type graph = nodes:int * edges:edge array

type pred = { index : int ; tail : int }

type min_paths = distance:int option array * predecessor:pred option array

type loop = { paths : min_paths ; is_updated : bool }

let relax_distance
  (state : loop)
  (index : int)
  (edge : edge)
  : loop =
  let { paths = ~distance, ~predecessor ; _ } = state in
  let from_, to_, weight = edge in
  match distance.(from_), distance.(to_) with
  | Some du, None ->
    distance.(to_) <- Some (du + weight);
    predecessor.(to_) <- Some { index ; tail = from_ };
    { paths = (~distance, ~predecessor) ; is_updated = true }
  | Some du, Some dv when du + weight < dv ->
      distance.(to_) <- Some (du + weight);
      predecessor.(to_) <- Some { index ; tail = from_ };
      { paths = ~distance, ~predecessor ; is_updated = true }
  | _ -> state

let relax_distances
  (dg : graph)
  ({ paths ; is_updated } : loop)
  (i : int)
  : [ `Continue of loop
    | `Stop of min_paths
    ] =
  let ~nodes, ~edges = dg in
  if i = nodes - 1 then `Stop paths
  else
    let iter =
      Array_utils.foldi relax_distance { paths ; is_updated } edges
    in
    if iter.is_updated then `Continue iter
    else `Stop paths

let find_min_paths ~(src : int) (nodes : int) (edges : edge array) =
  let distance = Array.init nodes (fun i -> if i = src then Some 0 else None) in
  let predecessor : pred option array = Array.init nodes (fun _ -> None) in
  let vertices = Array.init nodes Fun.id in
  Array_utils.fold_until
    (relax_distances (~nodes, ~edges))
    (fun { paths ; _ } -> paths)
    { paths = ~distance, ~predecessor ; is_updated = false }
    vertices

let find_cycle_edge distance edges =
  Array.find_mapi (fun index (from_, to_, weight) ->
    match distance.(from_), distance.(to_) with
    | Some du, Some dv when du + weight < dv ->
      Some (~index, ~tail:from_, ~head:to_)
    | _ -> None) edges

let bellman_ford ~(src : int) (nodes : int) (edges : edge array)
  : [ `Negative_cycle of int list
    | `No_negative_cycle of int array
    ] =
  let ~distance, ~predecessor = find_min_paths ~src nodes edges in
  let cycle_edge = find_cycle_edge distance edges in
  match cycle_edge with
  | None ->
    `No_negative_cycle (Array.map (Option.value ~default:Int.max_int) distance)
  | Some (~index:edge_index, ~tail:cycle_tail, ~head:cycle_start) ->
    (* This edge proves a negative cycle, so include it in the predecessor graph. *)
    predecessor.(cycle_start) <- Some { index = edge_index ; tail = cycle_tail };
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
        | Some { index ; tail } ->
          collect tail (curr :: seen) (index :: acc)
    in
    `Negative_cycle (collect start [] [])

open Utils

let bellman_ford = Bellman_ford.bellman_ford (module Char)

let _print_dist_tbl label tbl =
  Printf.printf "\n%s\n" label;
  tbl
  |> Hashtbl.to_seq
  |> List.of_seq
  |> List.sort (fun (n1, _) (n2, _) -> Char.compare n1 n2)
  |> List.iter (fun (node, (dist, pred_edge_opt)) ->
      match pred_edge_opt with
      | None ->
          Printf.printf "%c: dist=%d, pred=None\n" node dist
      | Some (from_, to_, weight) ->
          Printf.printf
            "%c: dist=%d, pred=(%c -> %c, %d)\n"
            node
            dist
            from_
            to_
            weight)

let pp_edge (from_, to_, weight) =
  Printf.sprintf "%c -> %c (%d)" from_ to_ weight
  
let pp_edge_opt edge =
  match edge with
  | None -> "None"
  | Some e -> pp_edge e

let pp_result ~src result =
  match result with
  | `No_negative_cycle distances ->
    print_endline "No negative cycle found.";
    List.iter (fun (node, distance) ->
      if node = src then ()
      else
        Printf.printf "dist(%c) = %s\n"
          node
          (if distance = Int.max_int then "∞" else Int.to_string distance)
    ) distances

  | `Negative_cycle cycle_edges ->
    print_endline "Negative cycle found:";
    List.iter (fun edge ->
      Printf.printf "- %s\n" (pp_edge edge))
      cycle_edges

let print_bellman_ford ~label ~src edges =
  Printf.printf "Example: [%s]\n" label;
  pp_result ~src (bellman_ford ~src edges);
  print_newline ()

let () =
  let edges = 
    [ ('a', '0', 3)
    ; ('0', 'a', -1)
    ; ('z', '0', 5)
    ; ('z', 'a', 5)
    ]
  in
  print_bellman_ford ~label:"OK cycle" ~src:'z' edges;

  let edges =
    [ ('a', '0', -6)
    ; ('0', 'a', -1)
    ; ('z', '0', 5)
    ; ('z', 'a', 5)
    ]
  in
  print_bellman_ford ~label:"Negative Cycle" ~src:'z' edges;

  let edges =
    [ ('a', '0', -6)
    ; ('0', 'a', -1)
    ]
  in
  print_bellman_ford ~label:"Negative Cycle src a" ~src:'a' edges;
  print_bellman_ford ~label:"Negative Cycle src 0" ~src:'0' edges;
  
  let edges =
    [ ('a', '0', -6)
    ; ('0', 'a', -1)
    ; ('0', 'b', 5)
    ]
  in
  print_bellman_ford ~label:"Augmented src a" ~src:'a' edges;
  print_bellman_ford ~label:"Augmented src 0" ~src:'0' edges;
  print_bellman_ford ~label:"Augmented src b" ~src:'b' edges;

  let edges = 
    [ ('a', '0', 3)
    ; ('0', 'a', -1)
    ; ('z', '0', 5)
    ; ('z', 'a', 5)
    ]
  in
  let module BellmanFord = Bellman_ford.Make (Char) in
  let dist, _num_nodes = BellmanFord.find_distances ~src:'z' edges in
  Printf.printf "Minimum distance to 'a' = %d\n" (fst @@ Hashtbl.find dist 'a');
  let predecessor_edge_of_a = BellmanFord.find_predecessor_edge 'a' dist in
  Printf.printf "Predecessor edge is: %s\n" (pp_edge_opt predecessor_edge_of_a);
  let predecessor_edge_of_0 = BellmanFord.find_predecessor_edge '0' dist in
  Printf.printf "Predecessor edge is: %s\n" (pp_edge_opt predecessor_edge_of_0);
  
  let edges =
  [ ('s', 'a', 2)
  ; ('a', 'b', 1)
  ; ('b', 'c', -4)
  ; ('c', 'a', 1)
  ; ('c', 'd', 3)
  ] in
  let dist, _ = BellmanFord.find_distances ~src:'s' edges in
  let cycle_entry = BellmanFord.find_cycle_entry edges dist in
  Printf.printf "Cycle entry is: %c\n" cycle_entry;
  
  let edges =
  [ ('c', 'd', 0)   (* outgoing edge from cycle to non-cycle node *)
  ; ('s', 'a', 0)
  ; ('a', 'b', 1)
  ; ('b', 'c', -4)
  ; ('c', 'a', 1)
  ] in
  let cycle_entry = BellmanFord.find_cycle_entry edges dist in
  Printf.printf "Cycle entry is: %c\n" cycle_entry;
  let cycle_edges = BellmanFord.collect_cycle cycle_entry dist in
  List.iter (fun edge ->
    Printf.printf "- %s\n" (pp_edge edge))
    cycle_edges
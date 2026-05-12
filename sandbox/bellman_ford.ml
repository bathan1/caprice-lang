open Utils

let bellman_ford = Bellman_ford.bellman_ford (module Char)

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


let intro_graph () =
  let edges = 
    [ ('a', '0', 3)
    ; ('0', 'a', -1)
    ; ('z', '0', 5)
    ; ('z', 'a', 5)
    ]
  in
  print_bellman_ford ~label:"OK cycle" ~src:'z' edges

let intro_graph_neg_cycle () =
  let edges =
    [ ('a', '0', -6)
    ; ('0', 'a', -1)
    ; ('z', '0', 5)
    ; ('z', 'a', 5)
    ]
  in
  print_bellman_ford ~label:"Negative Cycle" ~src:'z' edges

let () =
  intro_graph ();
  intro_graph_neg_cycle ();

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
  let dist = BellmanFord.find_shortest_paths ~src:'z' edges in
  Printf.printf "Minimum distance to 'a' = %d\n" (BellmanFord.find_distance 'a' dist);
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
  let dist = BellmanFord.find_shortest_paths ~src:'s' edges in
  let cycle_entry = BellmanFord.find_cycle_entry edges dist in
  Printf.printf "Cycle entry is: %c\n" cycle_entry;
  
  let edges =
    [ ('c', 'd', 0)   (* outgoing edge from cycle to non-cycle node *)
    ; ('s', 'a', 0)
    ; ('a', 'b', 1)
    ; ('b', 'c', -4)
    ; ('c', 'a', 1)
    ]
  in
  let cycle_entry = BellmanFord.find_relaxed_node edges dist in
  Printf.printf "First relaxed node found: %c\n" cycle_entry;
  let cycle_from_entry = BellmanFord.collect_cycle cycle_entry dist in
  List.iter (fun edge ->
    Printf.printf "- %s\n" (pp_edge edge))
    cycle_from_entry;

  let edges =
    [ ('s', 'a', 2)
    ; ('a', 'b', 1)
    ; ('b', 'c', -4)
    ; ('c', 'a', 1)
    ; ('c', 'd', 3)
    ]
  in
  let dist = BellmanFord.find_shortest_paths ~src:'z' edges in
  let cycle_entry = BellmanFord.find_cycle_entry edges dist in
  let cycle_from_entry = BellmanFord.collect_cycle cycle_entry dist in
  Printf.printf "Negative cycle found:\n";
  List.iter (fun edge ->
    Printf.printf "- %s\n" (pp_edge edge))
    cycle_from_entry;

open Utils

let bellman_ford = Bellman_ford.bellman_ford (module Char)

let pp_edge (from_, to_, weight) =
  Printf.sprintf "%c -> %c (%d)" from_ to_ weight

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
  let predecessor_edge_of_a = snd @@ Hashtbl.find dist 'a' in
  Printf.printf "Predecessor edge is: %s\n" (pp_edge predecessor_edge_of_a);
  let predecessor_edge_of_0 = snd @@ Hashtbl.find dist '0' in
  Printf.printf "Predecessor edge is: %s\n" (pp_edge predecessor_edge_of_0);
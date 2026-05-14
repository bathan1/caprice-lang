open Utils

let bellman_ford = Bellman_ford.bellman_ford (module String)
module BellmanFord = Bellman_ford.Make (String)

let pp_markdown_distance_table ~src distances =
  print_endline "| Node | Distance |";
  print_endline "|------|----------|";

  List.iter
    (fun (node, distance) ->
      if node = src then ()
      else
        Printf.printf
          "| $%s$  |   $%s$    |\n"
          (if node = "0*" then "0^*" else node)
          (if distance = Int.max_int then "∞" else Int.to_string distance))
    distances
;;

let pp_mermaid_cycle cycle_edges =
  print_endline "```mermaid";
  print_endline "graph LR";

  List.iter
    (fun (from_, to_, weight) ->
      Printf.printf
        "  n%s[\"%s\"] -->|\"%d\"| n%s[\"%s\"]\n"
        from_
        from_
        weight
        to_
        to_)
    cycle_edges;

  print_endline "```"
;;

let pp_result ~src result =
  match result with
  | `No_negative_cycle distances ->
    print_endline "```bash\nNo negative cycle found.\n```";
    print_endline "";
    pp_markdown_distance_table ~src distances

  | `Negative_cycle cycle_edges ->
    print_endline "```bash\nNegative cycle found!\n```";
    print_endline "";
    pp_mermaid_cycle cycle_edges
;;

let print_bellman_ford ~label ~src edges =
  Printf.printf "### Example: %s\n\n" label;
  pp_result ~src (bellman_ford ~src edges);
  print_endline ""
;;

let pp_edge (from_, to_, weight) =
  let from_ = if from_ = "0*" then "0^*" else from_ in
  let to_ = if to_ = "0*" then "0^*" else to_ in
  Printf.sprintf "%s -> %s (%d)" from_ to_ weight
  
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

let intro_graph () =
  let edges = 
    [ ("a", "0", 3)
    ; ("0", "a", -1)
    ; ("z", "0", 5)
    ; ("z", "a", 5)
    ]
  in
  print_bellman_ford ~label:"OK cycle" ~src:"z" edges
  

let augmented_graph () = 
  let edges =
    [ ("a", "0", -6)
    ; ("0", "a", -1)
    ; ("0", "b", 5)
    ]
  in
  print_bellman_ford ~label:"Augmented src a" ~src:"a" edges;
  print_bellman_ford ~label:"Augmented src 0" ~src:"0" edges;
  print_bellman_ford ~label:"Augmented src b" ~src:"b" edges

let predecessors_from_a () =
  let edges = 
    [ ("a", "0", 3)
    ; ("0", "a", -1)
    ; ("z", "0", 0)
    ; ("z", "a", 0)
    ]
  in
  let dist = BellmanFord.find_shortest_paths ~src:"z" edges in
  Printf.printf "Minimum distance to 'a' = %d\n" (BellmanFord.find_distance "a" dist);
  let predecessor_edge_of_a = BellmanFord.find_predecessor_edge "a" dist in
  Printf.printf "Predecessor edge is: %s\n" (pp_edge_opt predecessor_edge_of_a);
  let predecessor_edge_of_0 = BellmanFord.find_predecessor_edge "0" dist in
  Printf.printf "Predecessor edge is: %s\n" (pp_edge_opt predecessor_edge_of_0)
  
let sat_graph () =
  let edges =
    [ ("a", "0*", 1)
    ; ("0*", "a", 2)
    ; ("s", "0*", 0)
    ; ("s", "a", 0)
  ] in
  print_bellman_ford ~label:"SAT Graph" ~src:"s" edges

let sat_graph_offset () =
  let edges =
    [ ("a", "0*", -1)
    ; ("0*", "a", 2)
    ; ("s", "0*", 0)
    ; ("s", "a", 0)
  ] in
  print_bellman_ford ~label:"SAT Graph (with offset)" ~src:"s" edges
  
let cycle_entry () =
  let edges =
  [ ("s", "a", 2)
  ; ("a", "b", 1)
  ; ("b", "c", -4)
  ; ("c", "a", 1)
  ; ("c", "d", 3)
  ] in
  let dist = BellmanFord.find_shortest_paths ~src:"s" edges in
  let cycle_entry = BellmanFord.find_cycle_entry edges dist in
  Printf.printf "Cycle entry is: %s\n" cycle_entry

let intro_graph_neg_cycle () =
  let edges =
    [ ("a", "0*", -6)
    ; ("0*", "a", -1)
    ; ("r", "0*", 0)
    ; ("r", "a", 0)
    ]
  in
  print_bellman_ford ~label:"Negative Cycle" ~src:"r" edges

let run_bellman_ford () =
  sat_graph ();
  print_newline ();
  sat_graph_offset ();
  
intro_graph_neg_cycle ();
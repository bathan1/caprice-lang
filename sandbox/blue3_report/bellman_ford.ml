open Utils

let bellman_ford = Bellman_ford.bellman_ford (module Char)

let pp_edge (from_, to_, weight) =
  Printf.sprintf "%c -> %c (%d)" from_ to_ weight

let ok_example () =
  let edges =
    [ ('a', '0', 3)
    ; ('0', 'a', -1)
    ; ('z', '0', 5)
    ; ('z', 'a', 5)
    ]
  in
  match bellman_ford ~src:'z' edges with
  | `No_negative_cycle distances ->
    print_endline "No negative cycle found.";
    List.iter (fun (node, distance) ->
      Printf.printf "dist(%c) = %d\n" node distance)
      distances

  | `Negative_cycle cycle_edges ->
    print_endline "Negative cycle found:";
    List.iter (fun edge ->
      Printf.printf "- %s\n" (pp_edge edge))
      cycle_edges


let cycle_example () =
  let edges =
    [ ('a', '0', -6)
    ; ('0', 'a', -1)
    ; ('z', '0', 5)
    ; ('z', 'a', 5)
    ]
  in
  match bellman_ford ~src:'z' edges with
  | `No_negative_cycle distances ->
    print_endline "No negative cycle found.";
    List.iter (fun (node, distance) ->
      Printf.printf "dist(%c) = %d\n" node distance)
      distances

  | `Negative_cycle cycle_edges ->
    print_endline "Negative cycle found:";
    List.iter (fun edge ->
      Printf.printf "- %s\n" (pp_edge edge))
      cycle_edges

let () =
  ok_example ();
  cycle_example ()

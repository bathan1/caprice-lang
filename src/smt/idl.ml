(** IDL stands for Integer Difference Logic and it solves satisfiability
    of difference constraints in polynomial time relative to the number of edges
    (differences) and nodes (variables) via the Bellman Ford algorithm. *)
open Utils

type node =
  | Symbol_key of Uid.t
  | Z0

let nodes_equal n1 n2 =
  match n1, n2 with
  | Z0, Z0 -> true
  | Symbol_key u1, Symbol_key u2 -> Uid.equal u1 u2
  | _ -> false

type diff_constraint = { x : node ; y : node ; c : int }

type diff_constraint_literal =
  | Ineq of diff_constraint
  | Eq of diff_constraint * diff_constraint
(** Encodes the difference [x - y <= c] *)

let diff_constraints_equal l1 l2 =
  match l1, l2 with
  | c1, c2 when c1.c = c2.c
    && nodes_equal c1.x c2.x
    && nodes_equal c1.y c2.y -> true
  | _ -> false

type 'k diff_atom = { source : 'k Theory.literal ; diff : diff_constraint }

type 'k diff_literal =
  | Pos of 'k diff_atom
  | Neg of 'k diff_atom

type 'k edge =
  { from_ : int
  ; to_ : int
  ; weight : int
  ; source : 'k Theory.literal option
  }

type 'k constraint_graph = nodes:int * edges:'k edge array * index:int Uid.Map.t

let diff_from_leq left right : diff_constraint option =
  match Integer.affine_from_formula_opt left, Integer.affine_from_formula_opt right with
  | Some (Var_plus_const (x, kx)), Some (Var_plus_const (y, ky)) ->
    Some { x = Symbol_key x; y = Symbol_key y; c = ky - kx }
  | Some (Var_plus_const (x, kx)), Some (Const c) ->
    Some { x = Symbol_key x; y = Z0; c = c - kx }
  | Some (Const c), Some (Var_plus_const (y, ky)) ->
    Some { x = Z0; y = Symbol_key y; c = ky - c }
  | Some (Const c1), Some (Const c2) ->
    if c1 <= c2 then Some { x = Z0; y = Z0; c = 0 }
    else Some { x = Z0; y = Z0; c = -1 }
  | _ -> None

let find_diff_opt
  : type a. (a * a * bool) Binop.t ->
    (a, 'k) Formula.t ->
    (a, 'k) Formula.t ->
    diff_constraint_literal option =
  let ineq cst = Ineq cst in
  let eq cst1 cst2 = Eq (cst1, cst2) in
  fun binop left right ->
    match binop with
    | Less_than_eq -> Option.map ineq @@ diff_from_leq left right
    | Less_than ->
      (* left < right  ===  left <= right - 1 *)
      begin
        match diff_from_leq left right with
        | None -> None
        | Some d -> Some (ineq { d with c = d.c - 1 })
      end
    | Equal ->
      begin
        match diff_from_leq left right, diff_from_leq right left with
        | Some d1, Some d2 -> Some (eq d1 d2)
        | _ -> None
      end
    | _ -> None

let find_diff
  : type a. (a * a * bool) Binop.t -> (a, 'k) Formula.t -> (a , 'k) Formula.t -> diff_constraint_literal =
  fun binop left right ->
    match find_diff_opt binop left right with
    | None -> failwith
    (Printf.sprintf "\n[Idl.find_diff] No diff atom found in smt-atom: %s"
        (Formula.to_string
          ~key:Model.prefix_key
          (Formula.binop binop left right)))
    | Some diff -> diff

let mk_atom (source : 'k Theory.literal) (atom : 'k Theory.atom) : 'k diff_atom list =
  match atom with
  | Bool_key _ -> []
  | Predicate (binop, left, right) ->
    match find_diff binop left right with
    | Ineq diff ->
      [{ diff; source }]
    | Eq (diff1, diff2) ->
      [{ diff = diff1 ; source } ; { diff = diff2; source }]

let from_theory_literal (lit : 'k Theory.literal) : 'k diff_literal list =
  match lit with
  | Pos theory_atom ->
    theory_atom
    |> mk_atom lit
    |> List.map (fun atom -> Pos atom)
  | Neg theory_atom ->
    theory_atom
    |> mk_atom lit
    |> List.map (fun atom -> Neg atom)

let atom_from_literal (lit : 'k diff_literal) : 'k diff_atom =
  match lit with
  | Pos (_ as atom) -> atom
  | Neg { source ; diff = { x ; y ; c } } ->
    { source
    ; diff = { x = y; y = x; c = -c - 1 }
    }

(** [collect_constraints formula] returns the list of integer difference constraints in FORMULA *)
let collect_constraints (formula : 'k Theory.literal list)
  : 'k diff_atom list =
  formula
  |> List.concat_map from_theory_literal
  |> List.map atom_from_literal

let read_constraint_keys ({ x ; y ; _ } : diff_constraint) : Uid.t list =
  match x, y with
  | Symbol_key x, Symbol_key y when x = y -> [ x ]
  | Symbol_key x, Symbol_key y -> [ x ; y ]
  | Symbol_key key, Z0 | Z0, Symbol_key key -> [ key ]
  | _ -> []

let map_uid_indices (constraints : diff_constraint list) : int Uid.Map.t =
  constraints
  |> List.concat_map read_constraint_keys
  |> List.sort_uniq Uid.compare
  |> List.mapi (fun i uid -> (uid, i + 1))
  |> Uid.Map.of_list

let edges_from_constraint
  (source : 'k Theory.literal)
  ({ x; y; c } : diff_constraint)
  ~(nodes : int)
  ~(to_index : int Uid.Map.t)
  : 'k edge list =
  let get_index uid = Uid.Map.find uid to_index in
  match x, y with
  | Symbol_key x, Symbol_key y ->
    (* x - y <= c === y -> x *)
    [{ from_ = get_index y; to_ = get_index x; weight = c; source = Some source }]

  | Symbol_key x, Z0 ->
    [{ from_ = nodes - 1; to_ = get_index x; weight = c; source = Some source }]

  | Z0, Symbol_key y ->
    [{ from_ = get_index y; to_ = nodes - 1; weight = c; source = Some source }]

  | Z0, Z0 ->
    []

let to_graph
    (constraints : 'k diff_atom list)
    (key_to_index : int Uid.Map.t)
  : nodes:int * edges:'k edge array =
  let nodes =
    1 + Uid.Map.cardinal key_to_index + 1
  in
  let edges_constraints =
    constraints
    |> List.concat_map (fun { diff; source } ->
      edges_from_constraint source diff ~nodes ~to_index:key_to_index)
  in
  let dummy_root_edges =
    List.init (nodes - 1)
      (fun i ->
        { from_ = 0
        ; to_ = i + 1
        ; weight = 0
        ; source = None
        })
  in
  let edges = Array.of_list (edges_constraints @ dummy_root_edges) in
  ~nodes, ~edges

(** [to_constraint_graph formula] returns the 3-tuple graph representation
    (NODES, EDGES, UID_TO_INDEX) of FORMULA, where:
    - NODES is number of unique variables in FORMULA + 2
    - EDGES is a 3-tuple (SRC, DST, WEIGHT)
    - UID_TO_INDEX maps UIDs from FORMULA to their node id (index)

    Index [0] is reserved for dummy root node and index [NODES - 1]
    is reserved for the special "zero constant" node. *)
let to_constraint_graph (formula : 'k Theory.literal list)
  : 'k constraint_graph
  =
  let constraints = collect_constraints formula in
  let diffs = List.map
    (fun { diff ; _} -> diff) constraints
  in
  let index = map_uid_indices diffs in
  let ~nodes, ~edges = to_graph constraints index
  in
  ~nodes, ~edges, ~index

let relax_distance (acc : int option array * 'k edge option array * bool) (edge : 'k edge)
  : int option array * 'k edge option array * bool =
  let distance, predecessor, is_updated = acc in
  match distance.(edge.from_), distance.(edge.to_) with
  | None, _ -> acc
  | Some du, None ->
      distance.(edge.to_) <- Some (du + edge.weight);
      predecessor.(edge.to_) <- Some edge;
      distance, predecessor, true
  | Some du, Some dv ->
      if du + edge.weight < dv then (
        distance.(edge.to_) <- Some (du + edge.weight);
        predecessor.(edge.to_) <- Some edge;
        distance, predecessor, true
      ) else distance, predecessor, is_updated

let relax_distances (nodes : int) (edges : 'k edge array) (acc : int option array * 'k edge option array) (i : int)
  : [ `Continue of int option array * 'k edge option array
    | `Stop of int option array * 'k edge option array
    ] =
  if i = nodes - 1 then `Stop acc
  else
    let distance, predecessor = acc in
    let distance', predecessor', is_updated =
      Array.fold_left relax_distance (distance, predecessor, false) edges
    in
    if is_updated then `Continue (distance', predecessor')
    else `Stop (distance', predecessor')

(** [find_shortest_paths ~src nodes edges] runs the actual relaxation proc to
    find the shortest distances from SRC to every other node in the graph (NODES, EDGES) *)
let find_shortest_paths ~(src : int) (nodes : int) (edges : 'k edge array)
  : int option array * 'k edge option array =
  let distance = Array.init nodes (fun i -> if i = src then Some 0 else None) in
  let predecessor : 'k edge option array = Array.init nodes (fun _ -> None) in
  let vertices = Array.init nodes Fun.id in
  Array_utils.fold_left_until (relax_distances nodes edges) (distance, predecessor) vertices

let bellman_ford ~(src : int) (nodes : int) (edges : 'k edge array)
  : [ `Negative_cycle of 'k edge list
    | `No_negative_cycle of int array * 'k edge option array
    ] =
  let distance, predecessor = find_shortest_paths ~src nodes edges in
  let cycle_edge =
    Array.find_opt
      (fun edge ->
        match distance.(edge.from_), distance.(edge.to_) with
        | Some du, Some dv -> du + edge.weight < dv
        | _ -> false)
      edges
  in
  match cycle_edge with
  | None ->
    `No_negative_cycle
      (Array.map (Option.value ~default:Int.max_int) distance
      , predecessor)
  | Some edge ->
    (* This edge proves a negative cycle, so include it in the predecessor graph. *)
    predecessor.(edge.to_) <- Some edge;
    let rec move_back vertex n =
      if n = 0 then vertex
      else
        match predecessor.(vertex) with
        | None -> vertex
        | Some edge -> move_back edge.from_ (n - 1)
    in
    let start = move_back edge.to_ nodes in
    let rec collect curr acc =
      match predecessor.(curr) with
      | None ->
        acc
      | Some edge ->
        if List.exists
            (fun e ->
                e.from_ = edge.from_
                && e.to_ = edge.to_
                && e.weight = edge.weight)
            acc
        then
          edge :: acc
        else
          collect edge.from_ (edge :: acc)
    in
    `Negative_cycle (collect start [])


type 'k split_neq_case = lower:'k Theory.literal * upper:'k Theory.literal * eq:'k Theory.literal

let literal_has_same_diff l1 l2 =
  match from_theory_literal l1, from_theory_literal l2 with
  | [Pos a], [Pos b] -> diff_constraints_equal a.diff b.diff
  | [Neg a], [Neg b] ->
      let a' = atom_from_literal (Neg a) in
      let b' = atom_from_literal (Neg b) in
      diff_constraints_equal a'.diff b'.diff
  | _ -> false

let split_to_theory_clause ((~lower, ~upper, ~eq): 'k split_neq_case) : 'k Theory.literal list =
  [ lower ; upper ; eq ]

let find_split_opt (lit : 'k Theory.literal)
  : 'k split_neq_case option =
  let one = Formula.const_int 1 in
  match lit with
  | Neg Predicate (Equal, x, y) ->
    begin match Integer.reflect_int_opt x, Integer.reflect_int_opt y with
    | Some x', Some y' ->
        let lower = Theory.Predicate (Less_than_eq, x', (Formula.minus y' one)) in
        let upper = Theory.Predicate (Less_than_eq, (Formula.plus y' one), x') in
        let eq = Theory.Predicate (Equal, x, y) in
        Some (~lower:(Pos lower), ~upper:(Pos upper), ~eq:(Pos eq))
      | _ -> None
    end
  | _ -> None

let contains_literal_from_diff target lits =
  List.exists (fun lit -> literal_has_same_diff target lit) lits

let split_is_resolved lits ((~lower, ~upper, ~eq:_) : 'k split_neq_case) =
  contains_literal_from_diff lower lits
  || contains_literal_from_diff upper lits

let resolve_splits lits =
  List.fold_right
    (fun lit (graph_lits, splits) ->
      match find_split_opt lit with
      | None ->
          lit :: graph_lits, splits

      | Some split ->
          if split_is_resolved lits split then
            graph_lits, splits
          else
            graph_lits, split_to_theory_clause split :: splits)
    lits
    ([], [])

(** [solve_diff_logic formula] finds the tightest upper bounds of each integer variable in FORMULA *)
let solve_diff_logic (lits : 'k Theory.literal list) : 'k Theory.theory_solution =
  let lits', remaining_splits = resolve_splits lits in
  match remaining_splits with
  | _ :: _ as splits -> Theory_split splits
  | [] ->
    let ~nodes, ~edges, ~index = to_constraint_graph lits' in
    match bellman_ford nodes edges ~src:0 with
    | `Negative_cycle cycle_edges ->
      let core =
        cycle_edges
        |> List.filter_map (fun edge -> edge.source)
        |> List.sort_uniq compare
      in
      Theory_unsat core
    | `No_negative_cycle (distances, _) ->
      let z0_index = Array.length distances - 1 in
      let z0_dist = distances.(z0_index) in
      let local_model =
        Uid.Map.map
          (fun var_index ->
            Model.Int (distances.(var_index) - z0_dist))
          index
      in
      let model = Model.from_value_map local_model in
      Theory_sat model

(** IDL stands for Integer Difference Logic and it solves satisfiability
    of difference constraints in polynomial time relative to the number of edges
    (differences) and nodes (variables) via the Bellman Ford algorithm. *)
open Utils

module Node = struct
  type t =
    | Symbol_key of Uid.t
    | Zero
    | Root

  let compare a b =
    match a, b with
    | Root, Root -> 0
    | Root, _ -> -1
    | _, Root -> 1

    | Zero, Zero -> 0
    | Zero, _ -> -1
    | _, Zero -> 1

    | Symbol_key x, Symbol_key y -> Uid.compare x y
end

module NodeIterables = Set_map.Make_W (Node)
module NodeMap = NodeIterables.Map

type node = Node.t =
  | Symbol_key of Uid.t
  | Zero
  | Root

let nodes_equal n1 n2 =
  match n1, n2 with
  | Root, Root -> true
  | Zero, Zero -> true
  | Symbol_key u1, Symbol_key u2 -> Uid.equal u1 u2
  | _ -> false

let edges_equal (x1, y1, c1) (x2, y2, c2) =
  c1 = c2 && nodes_equal x1 x2 && nodes_equal y1 y2

type diff = { x : node ; y : node ; c : int }

let diffs_equal (d1 : diff) (d2 : diff) =
  d1.c = d2.c
  && nodes_equal d1.x d2.x
  && nodes_equal d1.y d2.y

type 'k diff_atom = { source : 'k Theory.literal ; diff : diff }

type 'k diff_literal =
  | Pos of 'k diff_atom
  | Neg of 'k diff_atom

type 'k constraint_graph =
  { edges : node Bellman_ford.edge list
  ; edge_sources : (node Bellman_ford.edge * 'k Theory.literal option) list
  ; vars : Uid.t list
  }

let leq_to_diff (left : Integer.affine) (right : Integer.affine) : diff =
  match left, right with
  | Var_plus_const (x, kx), Var_plus_const (y, ky) ->
    { x = Symbol_key x; y = Symbol_key y; c = ky - kx }
  | Var_plus_const (x, kx), Const c ->
    { x = Symbol_key x; y = Zero; c = c - kx }
  | Const c, Var_plus_const (y, ky) ->
    { x = Zero; y = Symbol_key y; c = ky - c }
  | Const c1, Const c2 ->
    if c1 <= c2 then { x = Zero; y = Zero; c = 0 }
    else { x = Zero; y = Zero; c = -1 }

let find_diffs
  : type a. (a * a * bool) Binop.t ->
    (a, 'k) Formula.t ->
    (a, 'k) Formula.t ->
    diff list =
  fun binop left right ->
    match Integer.affine_from_formula_opt left, Integer.affine_from_formula_opt right with
    | Some al, Some ar ->
      let diff = leq_to_diff al ar in
      begin match binop with
      | Less_than_eq -> [diff]
      | Less_than -> [{ diff with c = diff.c - 1 }]
      | Equal ->
        let flipped = leq_to_diff ar al in
        [diff; flipped]
      | _ -> []
      end
    | _ -> []

let make_atoms (source : 'k Theory.literal) (atom : 'k Theory.atom) : 'k diff_atom list =
  match atom with
  | Bool_key _ -> []
  | Predicate (binop, left, right) ->
    let diffs = find_diffs binop left right in
    List.map (fun diff -> { diff ; source }) diffs

let from_theory_literal (lit : 'k Theory.literal) : 'k diff_literal list =
  match lit with
  | Pos theory_atom ->
    theory_atom
    |> make_atoms lit
    |> List.map (fun atom -> Pos atom)
  | Neg theory_atom ->
    theory_atom
    |> make_atoms lit
    |> List.map (fun atom -> Neg atom)

let atom_from_literal (lit : 'k diff_literal) : 'k diff_atom =
  match lit with
  | Pos atom -> atom
  | Neg { source ; diff = { x ; y ; c } } ->
    { source
    ; diff = { x = y; y = x; c = -c - 1 }
    }

(** [collect_constraints formula] returns the list of integer difference constraints in FORMULA. *)
let collect_constraints (formula : 'k Theory.literal list)
  : 'k diff_atom list =
  formula
  |> List.concat_map from_theory_literal
  |> List.map atom_from_literal

let read_constraint_keys ({ x ; y ; _ } : diff) : Uid.t list =
  match x, y with
  | Symbol_key x, Symbol_key y when Uid.equal x y -> [x]
  | Symbol_key x, Symbol_key y -> [x; y]
  | Symbol_key key, Zero | Zero, Symbol_key key -> [key]
  | _ -> []

let edges_from_constraint
  (source : 'k Theory.literal)
  ({ x; y; c } : diff)
  : (node Bellman_ford.edge * 'k Theory.literal option) list =
  let mk from_ to_ =
    (from_, to_, c), Some source
  in
  match x, y with
  | Symbol_key x, Symbol_key y ->
    (* x - y <= c === y -> x *)
    [mk (Symbol_key y) (Symbol_key x)]
  | Symbol_key x, Zero ->
    [mk Zero (Symbol_key x)]
  | Zero, Symbol_key y ->
    [mk (Symbol_key y) Zero]
  | _ -> []

(** [to_graph formula] returns the graph representation of FORMULA.

    Since [Bellman_ford] now indexes arbitrary nodes internally, this graph
    stores edges directly as [(node, node, int)] triples instead of translating
    nodes to integers here.
*)
let to_graph (formula : 'k Theory.literal list) : 'k constraint_graph =
  let constraints = collect_constraints formula in

  let vars =
    constraints
    |> List.concat_map (fun { diff ; _ } -> read_constraint_keys diff)
    |> List.sort_uniq Uid.compare
  in

  let constraint_pairs =
    constraints
    |> List.concat_map (fun { diff; source } ->
      edges_from_constraint source diff)
  in

  let graph_nodes =
    Zero :: List.map (fun uid -> Symbol_key uid) vars
  in

  let dummy_pairs =
    graph_nodes
    |> List.map (fun node -> ((Root, node, 0), None))
  in

  let pairs = constraint_pairs @ dummy_pairs in

  { edges = pairs |> List.map fst
  ; edge_sources = pairs
  ; vars
  }

type 'k split_neq_case =
  lower:'k Theory.literal * upper:'k Theory.literal * eq:'k Theory.literal

let literal_has_same_diff l1 l2 =
  match from_theory_literal l1, from_theory_literal l2 with
  | [Pos a], [Pos b] -> diffs_equal a.diff b.diff
  | [Neg a], [Neg b] ->
    let a' = atom_from_literal (Neg a) in
    let b' = atom_from_literal (Neg b) in
    diffs_equal a'.diff b'.diff
  | _ -> false

let split_to_theory_clause ((~lower, ~upper, ~eq) : 'k split_neq_case)
  : 'k Theory.clause =
  Theory.clause [lower; upper; eq]

let find_split_opt (lit : 'k Theory.literal)
  : 'k split_neq_case option =
  let one = Formula.const_int 1 in
  match lit with
  | Neg Predicate (Equal, x, y) ->
    begin match Integer.reflect_int_opt x, Integer.reflect_int_opt y with
    | Some x', Some y' ->
      let lower =
        Theory.Predicate (Less_than_eq, x', Formula.minus y' one)
      in
      let upper =
        Theory.Predicate (Less_than_eq, Formula.plus y' one, x')
      in
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

let source_from_edge edge edge_sources =
  List.find_map
    (fun (edge', source) ->
      if edges_equal edge edge' then source else None)
    edge_sources

let bellman_ford = Bellman_ford.bellman_ford (module Node)

(** [solve_diff_logic literals] finds a satisfying integer model for LITERALS,
    or returns an unsat core when the constraint graph contains a negative cycle. *)
let solve_diff_logic (literals : 'k Theory.literal list)
  : 'k Theory.theory_solution =
  let lits, remaining_splits = resolve_splits literals in
  match remaining_splits with
  | _ :: _ as splits -> Theory.split splits
  | [] ->
    let { edges ; edge_sources ; vars } = to_graph lits in
    match bellman_ford ~src:Root edges with
    | `Negative_cycle edges ->
      let core =
        edges
        |> List.filter_map (fun edge -> source_from_edge edge edge_sources)
        |> List.sort_uniq compare
      in
      Theory.unsat core

    | `No_negative_cycle distances ->
      let distances =
        distances
        |> List.fold_left
             (fun acc (node, distance) -> NodeMap.add node distance acc)
             NodeMap.empty
      in

      let z0_dist = NodeMap.find Zero distances in

      let local_model =
        vars
        |> List.map (fun uid ->
          let var_dist = NodeMap.find (Symbol_key uid) distances in
          uid, Model.Int (var_dist - z0_dist))
        |> Uid.Map.of_list
      in

      let model = Model.from_value_map local_model in
      Theory.sat model

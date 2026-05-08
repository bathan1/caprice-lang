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

type diff = { x : node ; y : node ; c : int }

let diffs_equal l1 l2 =
  match l1, l2 with
  | c1, c2 when c1.c = c2.c
    && nodes_equal c1.x c2.x
    && nodes_equal c1.y c2.y -> true
  | _ -> false

type 'k diff_atom = { source : 'k Theory.literal ; diff : diff }

type 'k diff_literal =
  | Pos of 'k diff_atom
  | Neg of 'k diff_atom

type 'k constraint_graph =
  { nodes : int
  ; edges : Bellman_ford.edge array
  ; sources : 'k Theory.literal option array
  ; index : int Uid.Map.t
  }

let leq_to_diff (left : Integer.affine) (right : Integer.affine) : diff =
  match left, right with
  | Var_plus_const (x, kx), Var_plus_const (y, ky) ->
    { x = Symbol_key x; y = Symbol_key y; c = ky - kx }
  | Var_plus_const (x, kx), Const c ->
    { x = Symbol_key x; y = Z0; c = c - kx }
  | Const c, Var_plus_const (y, ky) ->
    { x = Z0; y = Symbol_key y; c = ky - c }
  | Const c1, Const c2 ->
    if c1 <= c2 then { x = Z0; y = Z0; c = 0 }
    else { x = Z0; y = Z0; c = -1 }

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
      | Less_than -> [ { diff with c = diff.c - 1 } ]
      | Equal ->
        let flipped = leq_to_diff ar al in
        [ diff ; flipped ]
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

let read_constraint_keys ({ x ; y ; _ } : diff) : Uid.t list =
  match x, y with
  | Symbol_key x, Symbol_key y when x = y -> [ x ]
  | Symbol_key x, Symbol_key y -> [ x ; y ]
  | Symbol_key key, Z0 | Z0, Symbol_key key -> [ key ]
  | _ -> []

let edges_from_constraint
  (source : 'k Theory.literal)
  ({ x; y; c } : diff)
  ~(to_index : int Uid.Map.t)
  : (Bellman_ford.edge * 'k Theory.literal option) list =
  let get_index uid = Uid.Map.find uid to_index in
  let mk from_ to_ =
    (from_, to_, c), Some source
  in
  match x, y with
  | Symbol_key x, Symbol_key y ->
    (* x - y <= c === y -> x *) [mk (get_index y) (get_index x)]
  | Symbol_key x, Z0 -> [mk 0 (get_index x)]
  | Z0, Symbol_key y -> [mk (get_index y) 0]
  | Z0, Z0 -> []

(** [to_graph formula] returns the 3-tuple graph representation
    (NODES, EDGES, UID_TO_INDEX) of FORMULA, where:
    - NODES is number of unique variables in FORMULA + 2
    - EDGES is a 3-tuple (SRC, DST, WEIGHT)
    - UID_TO_INDEX maps UIDs from FORMULA to their node id (index)

    Index [0] is reserved for dummy root node and index [NODES - 1]
    is reserved for the special "zero constant" node.
*)
let to_graph (formula : 'k Theory.literal list) : 'k constraint_graph =
  let constraints = collect_constraints formula in
  let index =
    constraints
    |> List.concat_map (fun { diff ; _ } -> read_constraint_keys diff)
    |> List.sort_uniq Uid.compare
    |> List.mapi (fun i uid -> (uid, i + 1))
    |> Uid.Map.of_list
  in
  let constraint_pairs = List.concat_map
    (fun { diff; source } ->
      edges_from_constraint source diff ~to_index:index)
    constraints
  in
  let nodes = 1 + Uid.Map.cardinal index + 1 in
  let dummy_pairs =
    List.init (nodes - 1) (fun i ->
      ((nodes - 1, i, 0), None))
  in
  let pairs = constraint_pairs @ dummy_pairs in
  let edges = pairs
    |> List.map fst
    |> Array.of_list
  in
  let sources =
    pairs
    |> List.map snd
    |> Array.of_list
  in

  { nodes; edges; sources; index }

type 'k split_neq_case = lower:'k Theory.literal * upper:'k Theory.literal * eq:'k Theory.literal

let literal_has_same_diff l1 l2 =
  match from_theory_literal l1, from_theory_literal l2 with
  | [Pos a], [Pos b] -> diffs_equal a.diff b.diff
  | [Neg a], [Neg b] ->
      let a' = atom_from_literal (Neg a) in
      let b' = atom_from_literal (Neg b) in
      diffs_equal a'.diff b'.diff
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
let solve_diff_logic (unit_clauses : 'k Theory.literal list) : 'k Theory.theory_solution =
  let lits', remaining_splits = resolve_splits unit_clauses in
  match remaining_splits with
  | _ :: _ as splits -> Theory_split splits
  | [] ->
    let { nodes; edges; sources; index } = to_graph lits' in
    match Bellman_ford.bellman_ford nodes edges ~src:(nodes - 1) with
    | `Negative_cycle edge_indices ->
      let core =
        edge_indices
        |> List.filter_map (fun i -> sources.(i))
        |> List.sort_uniq compare
      in
      Theory_unsat core
    | `No_negative_cycle distances ->
      let z0_dist = distances.(0) in
      let local_model =
        Uid.Map.map
          (fun var_index ->
            Model.Int (distances.(var_index) - z0_dist))
          index
      in
      let model = Model.from_value_map local_model in
      Theory_sat model

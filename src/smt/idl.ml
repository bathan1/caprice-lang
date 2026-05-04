open Utils
exception Graph_disconnected of int

type var =
  | Symbol_key of Uid.t
  | Z0

type diff_constraint = { x : var ; y : var ; c : int }

type diff =
  | Ineq of diff_constraint
  | Eq of diff_constraint * diff_constraint
(** Encodes the difference [x - y <= c] *)

let ineq cst = Ineq cst
let eq cst1 cst2 = Eq (cst1, cst2)

type 'k atom = { source : 'k Theory.literal ; diff : diff_constraint }

type 'k literal =
  | Pos of 'k atom
  | Neg of 'k atom

type 'k edge =
  { from_ : int
  ; to_ : int
  ; weight : int
  ; source : 'k Theory.literal option
  }
type 'k constraint_graph = nodes:int * edges:'k edge array * index:int Uid.Map.t


let diff_of_leq left right : diff_constraint option =
  match Integer.affine_from_formula left, Integer.affine_from_formula right with
  | Some (Var_plus_const (x, kx)), Some (Var_plus_const (y, ky)) ->
    Some { x = Symbol_key x; y = Symbol_key y; c = ky - kx }
  | Some (Var_plus_const (x, kx)), Some (Const c) ->
    Some { x = Symbol_key x; y = Z0; c = c - kx }
  | Some (Const c), Some (Var_plus_const (y, ky)) ->
    Some { x = Z0; y = Symbol_key y; c = ky - c }
  | Some (Const c1), Some (Const c2) ->
    if c1 <= c2 then Some { x = Z0; y = Z0; c = 0 }
    else Some { x = Z0; y = Z0; c = -1 }
  | _ ->
    None
let find_diff_opt
  : type a. (a * a * bool) Binop.t ->
    (a, 'k) Formula.t ->
    (a, 'k) Formula.t ->
    diff option =
  fun binop left right ->
    match binop with
    | Less_than_eq ->
      diff_of_leq left right |> Option.map ineq

    | Less_than ->
      (* left < right  ===  left <= right - 1 *)
      begin
        match diff_of_leq left right with
        | None -> None
        | Some d -> Some (ineq { d with c = d.c - 1 })
      end

    | Equal ->
      begin
        match diff_of_leq left right, diff_of_leq right left with
        | Some d1, Some d2 -> Some (eq d1 d2)
        | _ -> None
      end

    | _ ->
      None

let find_diff 
  : type a. (a * a * bool) Binop.t -> (a, 'k) Formula.t -> (a , 'k) Formula.t -> diff =
  fun binop left right -> 
    match find_diff_opt binop left right with
    | None -> failwith 
      (Printf.sprintf "No diff atom found in smt-atom: %s" 
        (Formula.to_string 
          ~uid:(fun uid -> Int.to_string (Uid.to_int uid))
          (Formula.binop binop left right)))
    | Some diff -> diff

let mk_atom (source : 'k Theory.literal) (atom : 'k Theory.atom) : 'k atom list =
  match atom with
  | Bool_key _ -> []
  | Predicate (binop, left, right) ->
    match find_diff binop left right with
    | Ineq diff ->
      [{ diff; source }]
    | Eq (diff1, diff2) ->
      [{ diff = diff1 ; source } ; { diff = diff2; source }]

let from_theory_literal (lit : 'k Theory.literal) : 'k literal list =
  match lit with
  | Pos theory_atom -> 
    theory_atom
    |> mk_atom lit
    |> List.map (fun atom -> Pos atom)
  | Neg theory_atom ->
    theory_atom
    |> mk_atom lit
    |> List.map (fun atom -> Neg atom)

let decode_literal (lit : 'k literal) : 'k atom =
  match lit with
  | Pos (_ as atom) -> atom
  | Neg { source; diff = { x; y; c } } ->
    {
      source;
      diff = { x = y; y = x; c = -c - 1 };
    }

(** [collect_constraints formula] returns the list of integer difference constraints in FORMULA *)
let collect_constraints (formula : 'k Theory.literal list)
  : 'k atom list =
  formula
  |> List.concat_map from_theory_literal
  |> List.map decode_literal

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
    (constraints : 'k atom list)
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

let bellman_ford ~(src : int) (nodes : int) (edges : 'k edge array) =
  let distance =
    Array.init nodes (fun i -> if i = src then Some 0 else None)
  in
  let predecessor : 'k edge option array =
    Array.init nodes (fun _ -> None)
  in

  let relax_edge edge =
    match distance.(edge.from_), distance.(edge.to_) with
    | None, _ ->
      ()

    | Some du, None ->
      distance.(edge.to_) <- Some (du + edge.weight);
      predecessor.(edge.to_) <- Some edge

    | Some du, Some dv ->
      if du + edge.weight < dv then (
        distance.(edge.to_) <- Some (du + edge.weight);
        predecessor.(edge.to_) <- Some edge
      )
  in

  for _ = 1 to nodes - 1 do
    Array.iter relax_edge edges
  done;

  let find_cycle_edge () =
    Array.find_opt
      (fun edge ->
        match distance.(edge.from_), distance.(edge.to_) with
        | Some du, Some dv -> du + edge.weight < dv
        | _ -> false)
      edges
  in

  match find_cycle_edge () with
  | None ->
    `No_negative_cycle
      ( Array.map (Option.value ~default:Int.max_int) distance
      , predecessor )
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

(** [idl formula] finds the tightest upper bounds of each integer variable in FORMULA

    {[
    open Smt

    module AsciiSymbol = Symbol.AsciiSymbol

    let () =
      let key c = Formula.symbol (AsciiSymbol.make_int c) in
      in
      let formula = Formula.and_ [
        Formula.binop Less_than_eq (key 'a') (Formula.const_int 2);
        Formula.binop Greater_than (key 'b') (key 'a');
      ] 
      in
      match Integer.solve_diff formula with
      | Solution.Sat model ->
          (* Access a (tight) upper bound: model.value (I 0) -> int option *)
          printf "SAT: upper bound on x = %d\n"
            (Option.value_exn (model.value (I 0)))
      | Unsat ->
          printf "UNSAT\n"
    ]}
*)
let idl (formula : 'k Theory.literal list) : 'k Theory.solution =
  let ~nodes, ~edges, ~index = to_constraint_graph formula in
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

let split_cases (formula : (bool, 'k) Formula.t) : (bool, 'k) Formula.t * int =
  let one = Formula.const_int 1 in
  let rec split (formula : (bool, 'k) Formula.t) : (bool, 'k) Formula.t * int =
    match formula with
    | Formula.Not (Formula.Binop (Equal, x, y)) ->
      begin match Integer.affine_from_formula x, Integer.affine_from_formula y with
      | Some ax, Some ay ->
        let x' = Integer.formula_from_affine ax in
        let y' = Integer.formula_from_affine ay in
        (* x != y  ==>  x <= y - 1 OR x >= y + 1 *)
        let leq =
          Formula.binop
            Less_than_eq
            x'
            (Formula.minus y' one)
        in
        let geq =
          Formula.binop
            Greater_than_eq
            x'
            (Formula.plus y' one)
        in
        Formula.binop Or leq geq, 1
      | _ -> formula, 0
      end
    | And ls ->
      let ls', count =
        List.fold_left
          (fun (acc, count) f ->
            let f', n = split f in
            (f' :: acc, count + n))
          ([], 0)
          ls
      in
      Formula.and_ (List.rev ls'), count
    | _ -> formula, 0
  in
  split formula

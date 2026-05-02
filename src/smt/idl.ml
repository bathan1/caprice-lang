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

type constraint_graph = nodes:int * edges:(int * int * int) array * int Uid.Map.t

type affine =
  | Const of int
  | Var_plus_const of Uid.t * int

let affine_of_formula : type a. (a, 'k) Formula.t -> affine option =
  function
  | Formula.Const_int c ->
    Some (Const c)
  | Formula.Key (I x) ->
    Some (Var_plus_const (x, 0))
  | Formula.Binop (Plus, Formula.Key (I x), Formula.Const_int c)
  | Formula.Binop (Plus, Formula.Const_int c, Formula.Key (I x)) ->
    Some (Var_plus_const (x, c))
  | Formula.Binop (Minus, Formula.Key (I x), Formula.Const_int c) ->
    Some (Var_plus_const (x, -c))
  | _ ->
    None

let diff_of_leq left right : diff_constraint option =
  match affine_of_formula left, affine_of_formula right with
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
          ~uid:Symbol.AsciiSymbol.to_string 
          (Formula.binop binop left right)))
    | Some diff -> diff

let mk_atom (source : 'k Theory.literal) (atom : 'k Theory.atom) : 'k atom list =
  match atom with
  | Bool_key _ ->
    failwith "Expected input to be a predicate"
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

let decode_literal (lit : 'k literal) : diff_constraint =
  match lit with
  | Pos { diff; _ } -> diff
  | Neg { diff = { x; y; c }; _ } -> { x = y; y = x; c = -c - 1 }

(** [collect_constraints formula] returns the list of integer difference constraints in FORMULA *)
let collect_constraints (formula : 'k Theory.literal list)
  : diff_constraint list =
  formula
  |> List.concat_map from_theory_literal
  |> List.map decode_literal

let read_constraint_keys ({ x ; y ; _ } : diff_constraint) : Uid.t list =
  match x, y with
  | Symbol_key x, Symbol_key y when x = y -> [ x ]
  | Symbol_key x, Symbol_key y -> [ x ; y ]
  | Symbol_key key, Z0 | Z0, Symbol_key key -> [ key ]
  | _ -> []

let index_constraint_keys (constraints : diff_constraint list) : int Uid.Map.t =
  constraints
  |> List.concat_map read_constraint_keys
  |> List.sort_uniq Uid.compare
  |> List.mapi (fun i uid -> (uid, i + 1)) (* Reserve index 0 for super-root node *)
  |> Uid.Map.of_list

let edges_from_constraints
  (constraints : diff_constraint list)
  (nodes : int)
  (key_to_index : int Uid.Map.t) 
  : (int * int * int) list =
  let get_index x = Uid.Map.find x key_to_index in
  List.filter_map
    (fun { x ; y ; c } ->
      match (x, y) with
      | Symbol_key x, Symbol_key y -> Some (get_index x, get_index y, c)
      | Symbol_key x, Z0 -> Some (get_index x, nodes - 1, c)
      | Z0, Symbol_key y -> Some (nodes - 1, get_index y, c)
      | _ -> None) constraints

let build_constraint_graph (constraints : diff_constraint list) (key_to_index : int Uid.Map.t) : constraint_graph =
  let nodes =
    1 + Uid.Map.cardinal key_to_index + 1 (* [0; x; y; z0] *)
  in
  let edges_constraints = edges_from_constraints constraints nodes key_to_index in
  let dummy_root_edges = List.init nodes (fun i -> (0, i, 0)) in
  let edges = Array.of_list (edges_constraints @ dummy_root_edges) in
  (~nodes, ~edges, key_to_index)

(** [to_constraint_graph formula] returns the 3-tuple graph representation
    (NODES, EDGES, UID_TO_INDEX) of FORMULA, where:
    - NODES is number of unique variables in FORMULA + 2
    - EDGES is a 3-tuple (SRC, DST, WEIGHT)
    - UID_TO_INDEX maps UIDs from FORMULA to their node id (index)

    Index [0] is reserved for dummy root node and index [NODES - 1]
    is reserved for the special "zero constant" node. *)
let to_constraint_graph (formula : 'k Theory.literal list) : constraint_graph =
  let constraints = collect_constraints formula in
  let keymap = index_constraint_keys constraints in
  build_constraint_graph constraints keymap

let bellman_ford ~(src : int) (nodes : int) (edges : (int * int * int) array) =
  let init =
    ( Array.init nodes (fun i -> if i = src then Some 0 else None),
      Array.init nodes (fun _ : int option -> None) )
  in
  let vertices = Array.init nodes (fun i -> i) in
  let relax_distances =
    fun (distance, predecessor) (u, v, w) ->
    match (distance.(u), distance.(v)) with
    | None , _ -> (distance, predecessor)
    | Some du, None ->
      let () =
        distance.(v) <- Some (du + w);
        predecessor.(v) <- Some u
      in
      (distance, predecessor)
    | Some du, Some dv ->
      let () =
        if du + w < dv then distance.(v) <- Some (du + w);
        predecessor.(v) <- Some u
      in
      (distance, predecessor)
  in
  let distance, predecessor =
    Array.fold_left
      (fun (distance, predecessor) i ->
        if i = nodes - 1 then (distance, predecessor)
        else Array.fold_left relax_distances (distance, predecessor) edges)
      init vertices
  in
  let rec find_cycle_start i =
    if i >= Array.length edges then None
    else
      let u, v, w = edges.(i) in
      match (distance.(u), distance.(v)) with
      | None, _ -> raise (Graph_disconnected u)
      | _, None -> raise (Graph_disconnected v)
      | Some du, Some dv when du + w < dv -> Some v
      | _ -> find_cycle_start (i + 1)
  in
  match find_cycle_start 0 with
  | None -> `No_negative_cycle (Array.map (Option.value ~default:Int.max_int) distance, predecessor)
  | Some vertex ->
    let rec move_back x i =
      if i = 0 then x
      else
        match predecessor.(x) with
        | None -> x
        | Some parent -> move_back parent (i - 1)
    in
    let cycle_vertex = move_back vertex nodes in
    let rec collect_cycle curr acc =
      if List.mem curr acc then curr :: acc
      else
        match predecessor.(curr) with
        | None -> curr :: acc
        | Some parent -> collect_cycle parent (curr :: acc)
    in
    `Negative_cycle (collect_cycle cycle_vertex [])

(** [solve_idl formula] finds the tightest upper bounds of each integer variable in FORMULA

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
  let ~nodes, ~edges, key_to_index = to_constraint_graph formula in
  match bellman_ford nodes edges ~src:0 with
  | `Negative_cycle cycle ->
    List.iter (Printf.printf "%d,") cycle;
    Theory_unsat []
  | `No_negative_cycle (distances, _) ->
    let offset = distances.(nodes - 1) in
    let local_model = Uid.Map.map (fun index ->
        Model.Int (offset - distances.(index))
      ) key_to_index
    in
    let model = Model.from_value_map local_model in
    Theory_sat model

open Utils

type int_bound = {
  lower : int option;
  upper : int option;
  nots : int list;
}

let greater_than_eq a b = Formula.binop Greater_than_eq a b
let greater_than a b = Formula.binop Greater_than a b
let less_than_eq a b = Formula.binop Less_than_eq a b
let less_than a b = Formula.binop Less_than a b

let symbol_int (uid : Uid.t) = Formula.symbol (I uid)

let constraints_for_var x { lower; upper; nots } =
  let base =
    []
    |> (fun acc ->
      match lower with
      | Some l -> greater_than_eq (Formula.symbol (I x)) (Formula.const_int l) :: acc
      | None -> acc)
    |> (fun acc ->
      match upper with
      | Some u -> less_than_eq (Formula.symbol (I x)) (Formula.const_int u) :: acc
      | None -> acc)
  in

  let nots_formula =
    nots
    |> List.map (fun n ->
      Formula.binop Not_equal (Formula.symbol (I x)) (Formula.const_int n)
    )
  in

  base @ nots_formula


let rebuild bounds_state rest =
  bounds_state
  |> List.concat_map (fun (x, b) -> constraints_for_var x b)
  |> (function
    | [] -> rest
    | [f] -> f :: rest
    | xs -> (xs @ rest))
  |> Formula.and_

let update_bounds (uid : Uid.t) f bounds_state =
  let existing =
    List.assoc_opt uid bounds_state
    |> Option.value ~default:{ lower=None; upper=None; nots=[] }
  in
  let updated = f existing in
  (uid, updated)
  :: List.remove_assoc uid bounds_state


let rec rewrite_int : type k.
  (int, k) Formula.t -> (int, k) Formula.t =
  function
  | Formula.Binop (Plus, a, b) ->
    Formula.binop Plus (rewrite_int a) (rewrite_int b)
  | Binop (Minus, a, b) ->
    Formula.binop Minus (rewrite_int a) (rewrite_int b)
  | t -> t


let rec linearize : type k.
  (int, k) Formula.t -> (Uid.t * int) option =
  function
  | Formula.Key (I x) ->
    Some (x, 0)
  | Binop (Plus, t, Const_int c) ->
    linearize t
    |> Option.map (fun (x, k) -> (x, k + c))
  | Binop (Plus, Const_int c, t) ->
    linearize t
    |> Option.map (fun (x, k) -> (x, k + c))

  | Binop (Minus, t, Const_int c) ->
    linearize t
    |> Option.map (fun (x, k) -> (x, k - c))
  | _ ->
    None

let append_neq 
  (uid : Uid.t)
  (val_neq : int)
  (bounds_state : (Uid.t * int_bound) list) =
  let existing =
    List.assoc_opt uid bounds_state
    |> Option.value ~default:{ lower=None; upper=None; nots=[]; }
  in
  let within_bounds =
    let lower_ok =
      match existing.lower with
      | None -> true
      | Some l -> val_neq >= l
    in
    let upper_ok =
      match existing.upper with
      | None -> true
      | Some u -> val_neq <= u
    in
    lower_ok && upper_ok
  in

  let appended =
    if not within_bounds then
      existing
    else
      { existing with
        nots =
          if List.mem val_neq existing.nots
          then existing.nots
          else val_neq :: existing.nots
      }
  in

  (uid, appended)
  :: List.remove_assoc uid bounds_state

(** [simplify_int_bounds solve expr] drops redundant inequalities from EXPR before SOLVE calls it 
*)
let simplify_int_bounds : 'k Formula.simplifier = fun solve expr ->
  let rec loop_over 
    (bounds_state : (Uid.t * int_bound) list)
    (rest : (bool, 'k) Formula.t list) =
    let next = loop_over bounds_state rest in
    function
    | Formula.Not (Formula.Binop (Binop.Equal, Const_int c, Key (I x)))
      | Not (Binop (Equal, Key (I x), Const_int c))
      | Binop (Not_equal, Const_int c, Key (I x))
      | Binop (Not_equal, Key (I x), Const_int c) -> (
        append_neq x c bounds_state, rest
      )
    | Binop (Less_than_eq, Const_int c1, rhs) -> 
      greater_than_eq rhs (Formula.const_int c1) |> next
    | Binop (Less_than, Const_int c1, rhs) ->
      greater_than rhs (Formula.const_int c1) |> next
    | Binop (Greater_than_eq, Const_int c1, rhs) ->
      less_than_eq rhs (Formula.const_int c1) |> next
    | Binop (Greater_than, Const_int c1, rhs) ->
      less_than rhs (Formula.const_int c1) |> next
    | Not (Binop (Less_than, a, b)) ->
      greater_than_eq a b |> next
    | Not (Binop (Less_than_eq, a, b)) ->
      greater_than a b |> next
    | Not (Binop (Greater_than, a, b)) ->
      less_than_eq a b |> next
    | Not (Binop (Greater_than_eq, a, b)) ->
      less_than a b |> next
    | Binop ((Less_than | Less_than_eq
      | Greater_than | Greater_than_eq) as op,
      lhs,
      Const_int c2) -> (
        let lhs = rewrite_int lhs in
        match linearize lhs with
        | Some (x, k') ->
          let c = c2 - k' in 
          let bounds_state = (
            match op with
            | Less_than_eq -> (
              bounds_state
              |> update_bounds 
                x 
                (fun b -> {
                  b with upper = Some (
                    match b.upper with
                    | None -> c
                    | Some u -> min u c
                  )
                })
            )
            | Less_than -> (
              bounds_state
              |> update_bounds
                x
                (fun b -> { 
                  b with upper = Some (
                    match b.upper with
                    | None -> c - 1
                    | Some u -> min u (c - 1)
                  ) 
                })
            )
            | Greater_than_eq -> (
              bounds_state
              |> update_bounds 
                x 
                (fun b -> {
                  b with lower = Some (
                    match b.lower with
                    | None -> c
                    | Some l -> max l c
                  )
                })
            )
            | Greater_than -> (
              bounds_state
              |> update_bounds
                x
                (fun b -> {
                  b with lower = Some (
                    match b.lower with
                    | None -> c + 1
                    | Some l -> max l (c + 1)
                  )
                })
            )
            | _ -> bounds_state
          ) in (bounds_state, rest)
        | None ->
          (* Should never hit... *)
          (bounds_state, Formula.binop op lhs (Formula.const_int c2) :: rest)
      )
    | And xs ->
      xs
      |> List.fold_left (fun (st, rest_acc) f -> 
        loop_over st rest_acc f
      ) (bounds_state, rest)
    | f -> (bounds_state, f :: rest)
  in
  let bounds, rest = loop_over [] [] expr in 
  rebuild bounds rest
  |> solve

type var =
  | Symbol_key of Uid.t
  | Z0

type diff_constraint = {
  (** Variable (id) to subtract. *)
  x : var;

  (** Variable (id) that subtracts [x]. *)
  y : var;

  (** Intepreted as an int {i literal} *)
  c : int;
}

let rec extract (formula : (bool, 'k) Formula.t) : diff_constraint list =
  let open Formula in
  formula
  |> function
  | Not Binop (Greater_than, Key I x, Key I y)
    | Not Binop (Less_than, Key I y, Key I x) ->
    extract (less_than_eq (symbol_int x) (symbol_int y))

  | Not Binop (Greater_than_eq, Key I x, Key I y) ->
    extract (less_than (symbol_int x) (symbol_int y))

  | Not Binop (Less_than_eq, Key I x, Key I y) ->
    extract (greater_than (symbol_int x) (symbol_int y))

  | Not Binop (Less_than_eq, Const_int c, Key I x)
    | Not Binop (Greater_than_eq, Key I x, Const_int c) ->
    extract (less_than (symbol_int x) (const_int c))

  | Not Binop (Greater_than, Const_int c, Key I x)
    | Not Binop (Less_than, Key I x, Const_int c) ->
    extract (greater_than (symbol_int x) (const_int c))

  | Not Binop (Less_than, Const_int c, Key I x)
    | Not Binop (Greater_than, Key I x, Const_int c) ->
    extract (greater_than (symbol_int x) (const_int c))

  | Not Binop (Greater_than_eq, Const_int c, Key I x)
    | Not Binop (Less_than_eq, Key I x, Const_int c) ->
    extract (greater_than (symbol_int x) (const_int c))

  (* x = c -> (x - 0 <= c) and (0 - y) <= -c *)
  | Binop (Equal, Key I x, Const_int c)
    | Binop (Equal, Const_int c, Key I x) ->
    [ { x = Symbol_key x; y = Z0; c; };
      {x = Z0; y = Symbol_key x; c = -c } ]

  (* x = y -> (x - y) <= 0 and (y - x) <= 0*)
  | Binop (Equal, Key I x, Key I y) ->
    [ { x = Symbol_key x; y = Symbol_key y; c = 0 };
      { x = Symbol_key y; y = Symbol_key x; c = 0 } ]

  (* x <= y -> (x - y <= 0)
        y >= x -> (x - y <= 0)
        not (x > y) -> x <= y -> (x - y) <= 0 *)
  | Binop (Less_than_eq, Key I x, Key I y)
    | Binop (Greater_than_eq, Key I y, Key I x) ->
    [{ x = Symbol_key x; y = Symbol_key y; c = 0 }]

  (* x <= c -> (x - 0) <= c
        c >= x -> (x - 0) <= c
        not (x > c) -> x <= c -> (x - 0) <= c *)
  | Binop (Less_than_eq, Key I x, Const_int c)
    | Binop (Greater_than_eq, Const_int c, Key I x) ->
    [{ x = Symbol_key x; y = Z0; c }]

  (* x < c -> x - 0 <= c - 1 *)
  | Binop (Less_than, Key I x, Const_int c)
    | Binop (Greater_than, Const_int c, Key I x) ->
    [{ x = Symbol_key x; y = Z0; c = c - 1 }]

  (* x >= c -> 0 - x <= -c
       not (x < c) -> x >= c -> (0 - x) <= -c *)
  | Binop (Greater_than_eq, Key I x, Const_int c)
    | Binop (Less_than_eq, Const_int c, Key I x) ->
    [ {x = Z0; y = Symbol_key x; c = -c}  ]

  (* x > c -> (0 - x) <= -(c + 1) *)
  | Binop (Greater_than, Key I x, Const_int c)
    | Binop (Less_than, Const_int c, Key I x) ->
    [{ x = Z0; y = Symbol_key x; c = -(c + 1) }]

  (* x > y -> (y - x) <= -1 (difference is at least 1) *)
  | Binop (Greater_than, Key I x, Key I y)
    | Binop (Less_than,    Key I y, Key I x) ->
    [{ x = Symbol_key y; y = Symbol_key x; c = -1 }]

  (* x + c <= y  ->  x - y <= -c *)
  | Binop (Less_than_eq, Binop (Plus, Key I x, Const_int c), Key I y)
    | Binop (Less_than_eq, Binop (Plus, Const_int c, Key I x), Key I y) ->
    [{ x = Symbol_key x; y = Symbol_key y; c = -c }]

  (* y <= x + c  ->  y - x <= c *)
  | Binop (Less_than_eq, Key I y, Binop (Plus, Key I x, Const_int c))
    | Binop (Less_than_eq, Key I y, Binop (Plus, Const_int c, Key I x)) ->
    [{ x = Symbol_key y; y = Symbol_key x; c }]

  (* x - c <= y  ->  x - y <= c *)
  | Binop (Less_than_eq, Binop (Minus, Key I x, Const_int c), Key I y) ->
    [{ x = Symbol_key x; y = Symbol_key y; c }]

  (* y <= x - c  ->  y - x <= -c *)
  | Binop (Less_than_eq, Key I y, Binop (Minus, Key I x, Const_int c)) ->
    [{ x = Symbol_key y; y = Symbol_key x; c = -c }]

  | And exprs ->
    exprs
    |> List.fold_left (fun a_acc expr ->
      let a = extract expr in
      List.rev_append a a_acc
    ) []
    |> fun a -> List.rev a
  | _ -> []
;;

module UidMap = Map.Make (Uid)

let normalize (constraints : diff_constraint list) =
  let vars =
    constraints
    |> List.concat_map (fun a -> 
      match a.x, a.y with
      | Symbol_key x, Symbol_key y -> [x; y]
      | Symbol_key key, Z0 | Z0, Symbol_key key -> [key]
      | _ -> []
    )
    |> List.sort_uniq Uid.compare
  in
  let key_to_index =
    vars
    |> List.mapi (fun i v -> (v, i + 1))
    |> UidMap.of_list
  in
  let n = 1 + UidMap.cardinal key_to_index + 1
  (* [0; x; y; z0] *)
  in
  let get_index x = UidMap.find x key_to_index in
  let vertices = Array.init n (fun i -> i) in
  let edges_constraints = constraints |> List.filter_map (fun {x; y; c;} -> (
    match x, y with
    | Symbol_key x, Symbol_key y -> Some (get_index x, get_index y, c)
    | Symbol_key x, Z0 -> Some (get_index x, n - 1, c)
    | Z0, Symbol_key y -> Some (n - 1, get_index y, c)
    | _ -> None
  ))
  in
  let dummy_root_edges =
    List.init n (fun i -> (0, i, 0))
  in
  let edges = Array.of_list (edges_constraints @ dummy_root_edges) in
  vertices, edges, key_to_index

let bellman_ford (vertices : int array) (edges : (int * int * int) array) =
  let n = Array.length vertices in
  let _, (distance, predecessor) =
    Array.fold_left
      (fun (i, (distance, predecessor)) _ ->
        if i = n - 1 then
          (i + 1, (distance, predecessor))
        else
          let next_distance, next_predecessor =
            Array.fold_left
              (fun (distance, predecessor) (u, v, w) ->
                match (distance.(u), distance.(v)) with
                | du, _ when du = Int.max_int -> (distance, predecessor)
                | min_dist_to_u, dv when dv = Int.max_int ->
                  distance.(v) <- (min_dist_to_u + w);
                  predecessor.(v) <- u;
                  (distance, predecessor)
                | min_dist_to_u, min_dist_to_v ->
                  if min_dist_to_u + w < min_dist_to_v then
                    distance.(v) <- (min_dist_to_u + w);
                  predecessor.(v) <- u;
                  (distance, predecessor))
              (distance, predecessor)
              edges
          in
          (i + 1, (next_distance, next_predecessor)))
      (0, ([||], [||]))
      vertices
  in
  (* detect negative cycle and print it *)
  let cycle_start = 
    edges |> Array.fold_left (fun acc (u, v, w) ->
      match acc with
      | Some _ -> acc
      | None ->
        match (predecessor.(v), predecessor.(u)) with
        | _, _ ->
          begin 
            match distance.(u), distance.(v) with 
            | du, dv when (du = Int.max_int || dv = Int.max_int) -> None
            | du, dv ->
              if du + w < dv then
                Some v
              else
                None
            end
    ) None
  in
  match cycle_start with
  | None ->
    `No_negative_cycle (
      distance,
      predecessor
    )
  | Some v ->
    let rec move_back x i =
      if i = 0 then x
      else move_back predecessor.(x) (i - 1)
    in
    let cycle_vertex = move_back v n in

    let rec collect_cycle curr acc =
      if List.mem curr acc then
        curr :: acc
      else
        let parent = predecessor.(curr) in
        collect_cycle parent (curr :: acc)
    in

    let cycle = collect_cycle cycle_vertex [] in
    `Negative_cycle cycle

let is_int_diff_solvable (expr : (bool, 'k) Formula.t) : bool =
  match expr with
  | e when
    Formula.contains_binop Binop.Modulus e ||
    Formula.contains_binop Binop.Divide e ||
    Formula.contains_binop Binop.Times e ||
    Formula.contains_binop Binop.Or e -> false
  | _ -> true
;;

(** [solve_int_diff expr] finds the tightest upper bounds of each integer variable in EXPR

    {3 Example}
    {[
    open Smt.Integer
    open Smt.Binop
    open Smt.Symbol

    let () =
      let key c = Key (AsciiSymbol.make_int c) in
      in
      let formula = And [
        Binop (Less_than_eq, key 'a', Const_int 2);
        Binop (Greater, key 'b', key 'a');
      ] 
      in
      match solve_int_diff formula with
      | Sat model ->
          (* Access a (tight) upper bound: model.value (I 0) -> int option *)
          printf "SAT: upper bound on x = %d\n"
            (Option.value_exn (model.value (I 0)))
      | Unsat ->
          printf "UNSAT\n"
    ]
*)
let solve_int_diff (expr : (bool, 'k) Formula.t) : 'k Solution.t =
  expr
  |> extract
  |> normalize
  |> fun (vertices, edges, key_to_index) -> bellman_ford vertices edges
  |> function
  | `Negative_cycle _ -> Solution.Unsat
  | `No_negative_cycle (distances, _) ->
    let n = Array.length distances in 
    let offset = distances.(n - 1) in
    let keys = (
      key_to_index
      |> UidMap.to_list
      |> List.map (fun (key, _) -> key)
    ) in
    let model = Model.of_local
      keys
      ~lookup:(fun symbol_key ->
        match UidMap.find_opt symbol_key key_to_index with
        | None -> None
        | Some i ->
          Some (-1 * (distances.(i) - offset))
      )
    in
    Solution.Sat model

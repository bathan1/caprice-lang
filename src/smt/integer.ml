open Utils

(** [symbol uid] is an int symbol with UID wrapped over a [Formula.Key] *)
let symbol (uid : Uid.t) = Formula.symbol (I uid)

module Set = Set.Make (Int)

let linearize f = 
  match f with
  | Formula.Binop ((Less_than_eq | Less_than) as binop, (Binop (Plus, Key I x, Key I y)), Key I z) when x = z -> (
    Formula.binop binop (symbol y) (Formula.const_int 0)
  )
  | Formula.Binop (
      (Less_than_eq | Less_than) as binop,
      (Binop (
        Plus,
        Key I x,
        Const_int a
      )),
      Const_int b
    ) -> Formula.binop binop (symbol x) (Formula.const_int (b - a))

  | Formula.Binop (
      (Less_than_eq | Less_than | Equal) as binop,
      Const_int c,
      (Binop (
        (Plus | Minus) as op,
        Key I a,
        Key I b
      ))
    )
  | Formula.Binop (
      (Less_than_eq | Less_than | Equal) as binop,
      (Binop (
        (Plus | Minus) as op,
        Key I a,
        Key I b
      )),
      Const_int c
    ) -> (
      match op with
      | Plus -> 
        Formula.binop binop 
          (symbol a)
          (Formula.binop Minus (Formula.const_int c) (symbol b))
      | Minus -> 
        Formula.binop binop 
          (symbol a)
          (Formula.binop Plus (Formula.const_int c) (symbol b))
      | _ -> failwith "unreachable"
    )
  | f -> f

let to_propositional 
    ?(to_symbol : int -> (bool, 'k) Symbol.t =
    fun uid -> 
    uid 
    |> Uid.of_int
    |> fun uid -> Symbol.B uid
    )
  (f : (bool, 'k) Formula.t) =
  let counter = ref 0 in
  let n = Formula.count f in
  let hash = Hashtbl.create n in
  let rec aux f = 
    match f with
    | Formula.Not Binop (
        Equal,
        _,
        _
      )
    | Formula.Binop (
        (Less_than_eq | Less_than | Equal),
        _, _
      ) as atomic ->
        let count = !counter in
        let prop_sym = to_symbol count in
        let resolved_uid = Symbol.to_uid prop_sym in
        let prop_formula = Formula.symbol prop_sym in
        counter := count + 1;
        Hashtbl.add hash resolved_uid atomic;
        prop_formula
    | And ls ->
      ls
      |> List.map aux
      |> Formula.and_
    | expr -> expr
  in
  let bool_f = aux f in
  bool_f, Hashtbl.to_seq hash |> Uid.Map.of_seq
;;

let prune : type k. (bool, k) Formula.t list -> (bool, k) Formula.t list =
  fun clauses ->
  let find_or_default key map = 
    match Uid.Map.find_opt key map with
    | Some v -> v
    | None -> (
      Int.min_int, (* greatest lower bound *)
      Int.max_int, (* lowest upper bound *)
      Set.empty, (* not equal list *)
      Set.empty
    )
  in
  clauses
  |> List.fold_left (
    fun (acc, other) clause ->
    let aux clause =
      match clause with
      (* neq case *)
      | Formula.Not (Binop (Equal, Const_int c, Key I key))
        | Not (Binop (Equal, Key I key, Const_int c)) -> (
          let lower, upper, neq, eq = find_or_default key acc in
          let next_neq_set = Set.add c neq in
          let next = Uid.Map.add key (lower, upper, next_neq_set, eq) acc
          in
          next, other
        )

      (* eq case *)
      | Formula.Binop (Equal, Const_int c, Key I key)
        | Formula.Binop (Equal, Key I key, Const_int c) ->
        let lower, upper, neq, eq = find_or_default key acc in
        let next_eq_set = Set.add c eq in
        let next = Uid.Map.add key (lower, upper, neq, next_eq_set) acc
        in
        next, other

      (* lower bounds *)
      | Binop (Less_than_eq, Const_int c, Key I key)
        -> (
          let lower, upper, neq, eq = find_or_default key acc in
          let next = Uid.Map.add key (max lower c, upper, neq, eq) acc in
          next, other
        )
      | Binop (Less_than, Const_int c, Key I key) -> (
          let lower, upper, neq, eq = find_or_default key acc in
          let next = Uid.Map.add key (max lower (c + 1), upper, neq, eq) acc in
          next, other
        )

      (* upper bounds *)
      | Binop (Less_than_eq, Key I key, Const_int c) -> (
          let lower, upper, neq, eq = find_or_default key acc in
          let next = Uid.Map.add key (lower, min upper c, neq, eq) acc in
          next, other
        )
      | Binop (Less_than, Key I key, Const_int c) -> (
          let lower, upper, neq, eq = find_or_default key acc in
          let next = Uid.Map.add key (lower, min upper (c - 1), neq, eq) acc in
          next, other
        )
      | f -> acc, f :: other
    in
    aux clause
  ) (Uid.Map.empty, [])
  |> fun (bounds_map, other_clauses) -> 
  bounds_map
  |> Uid.Map.to_list
  |> List.concat_map (fun (uid, (lower, upper, neq, eq)) ->
    let is_impossible_bound = lower > upper in
    let num_eq = Set.cardinal eq in
    let is_eqs_impossible =
      (num_eq > 1) ||
      (Set.cardinal (Set.inter eq neq) > 0) ||
      Set.exists (fun veq -> lower > veq || veq > upper) eq
    in
    if is_impossible_bound || is_eqs_impossible then
      [Formula.const_bool false]
    else
      let variable = Formula.symbol (I uid) in
      let nontrivial_neqs = Set.filter (fun v -> lower < v && v < upper) neq
      in
      let neq_formulas = (
        nontrivial_neqs
        |> Set.to_list
        |> List.map (fun v -> 
          Formula.not_ (
            Formula.binop Equal variable (Formula.const_int v)
          )
        )
      ) in
      if num_eq == 1 then
        let value_eq = Set.find_first (fun _ -> true) eq in
        (Formula.binop Equal variable (Formula.const_int value_eq))
        :: neq_formulas
      else
        let lower_neq = Set.find_opt lower neq 
        in
        let upper_neq = Set.find_opt upper neq
        in
        let resolved_lower, resolved_upper = match lower_neq, upper_neq with
          | None, None -> 
            lower, upper
          (* drop neq and increment lower bound *)
          | Some lower_bound_neq, None -> 
            lower_bound_neq + 1, upper 
          (* drop neq and decrement upper bound *)
          | None, Some upper_bound_neq -> lower, upper_bound_neq - 1
          | Some lower_bound_eq, Some upper_bound_eq -> lower_bound_eq + 1, upper_bound_eq - 1
        in
        match resolved_lower, resolved_upper with
        | lb, rb when lb = Int.min_int && rb = Int.max_int -> neq_formulas
        | lb, rb when lb = Int.min_int -> 
          (Formula.binop Less_than_eq variable (Formula.const_int rb)) :: neq_formulas
        | lb, rb when rb = Int.max_int -> 
          (Formula.binop Less_than_eq (Formula.const_int lb) variable) :: neq_formulas
        | lb, rb -> 
          (Formula.binop Less_than_eq (Formula.const_int lb) variable) ::
          (Formula.binop Less_than_eq variable (Formula.const_int rb)) ::
          neq_formulas
  )
  |> fun rewritten ->
  rewritten @ other_clauses
;;

let rewrite : type k. (bool, k) Formula.t -> (bool, k) Formula.t =
  fun f ->
  let open Formula in
  let int_symbol key = symbol (I key) in
  let handle_neq left right =
    let right_minus_one = binop Plus right (const_int (-1)) in
    let right_plus_one = binop Plus right (const_int 1) in
    let left_ineq = binop Less_than_eq left right_minus_one in
    let right_ineq = binop Less_than_eq right_plus_one left in
    binop Or left_ineq right_ineq
  in
  let rec normalize_unit : type a. (a, k) t -> (a, k) t =
    function
    | And ls ->
      ls
      |> List.map (fun clause -> normalize_unit clause)
      |> and_
    (* neqs into disjunctions that bellman ford can solve *)
    | Not Binop (Equal, Key I left, Key I right) ->
      handle_neq (int_symbol left) (int_symbol right)
    (* x != C *)
    | Not Binop (Equal, Key I key, Const_int c) ->
      handle_neq (int_symbol key) (const_int c)
    (* C != x *)
    | Not Binop (Equal, Const_int c, Key I key) -> 
      handle_neq (int_symbol key) (const_int c)

    | f -> 
      f
  in
  f
  |> Formula.clauses_from
  |> List.map linearize
  |> prune
  |> List.map normalize_unit
  |> Formula.and_
;;


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

let rec extract_idl (formula : (bool, 'k) Formula.t) : diff_constraint list =
  let binop = Formula.binop in
  let const_int = Formula.const_int in
  formula
  |> function
    | Not Binop (Less_than, Key I y, Key I x) ->
    extract_idl (binop Less_than_eq (symbol x) (symbol y))

  | Not Binop (Less_than_eq, Key I x, Key I y) ->
    extract_idl (binop Greater_than (symbol x) (symbol y))

  | Not Binop (Less_than_eq, Const_int c, Key I x) ->
    extract_idl (binop Less_than (symbol x) (const_int c))

    | Not Binop (Less_than, Key I x, Const_int c) ->
    extract_idl (binop Greater_than (symbol x) (const_int c))

  | Not Binop (Less_than, Const_int c, Key I x) ->
    extract_idl (binop Greater_than (symbol x) (const_int c))

    | Not Binop (Less_than_eq, Key I x, Const_int c) ->
    extract_idl (binop Greater_than (symbol x) (const_int c))

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
  | Binop (Less_than_eq, Key I x, Key I y) ->
    [{ x = Symbol_key x; y = Symbol_key y; c = 0 }]

  (* x <= c -> (x - 0) <= c
        c >= x -> (x - 0) <= c
        not (x > c) -> x <= c -> (x - 0) <= c *)
  | Binop (Less_than_eq, Key I x, Const_int c) ->
    [{ x = Symbol_key x; y = Z0; c }]

  (* x < c -> x - 0 <= c - 1 *)
  | Binop (Less_than, Key I x, Const_int c) ->
    [{ x = Symbol_key x; y = Z0; c = c - 1 }]

  (* x >= c -> 0 - x <= -c
       not (x < c) -> x >= c -> (0 - x) <= -c *)
  | Binop (Less_than_eq, Const_int c, Key I x) ->
    [ {x = Z0; y = Symbol_key x; c = -c}  ]

  (* x > c -> (0 - x) <= -(c + 1) *)
  | Binop (Less_than, Const_int c, Key I x) ->
    [{ x = Z0; y = Symbol_key x; c = -(c + 1) }]

  (* x > y -> (y - x) <= -1 (difference is at least 1) *)
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
      let a = extract_idl expr in
      List.rev_append a a_acc
    ) []
    |> fun a -> List.rev a
  | _ -> []
;;

let is_idl_clause : type k. (bool, k) Formula.t -> bool = function
  | Formula.Binop (Less_than, Key (I _), Key (I _))
  | Formula.Binop (Less_than_eq, Key (I _), Key (I _))
  | Formula.Binop (Less_than, Const_int _, Key (I _))
  | Formula.Binop (Less_than_eq, Const_int _, Key (I _))
  | Formula.Binop (Less_than, Key (I _), Const_int _)
  | Formula.Binop (Less_than_eq, Key (I _), Const_int _)
  | Formula.Not (Formula.Binop (Less_than, Key (I _), Key (I _)))
  | Formula.Not (Formula.Binop (Less_than_eq, Key (I _), Key (I _)))
  | Formula.Not (Formula.Binop (Less_than, Const_int _, Key (I _)))
  | Formula.Not (Formula.Binop (Less_than_eq, Const_int _, Key (I _)))
  | Formula.Not (Formula.Binop (Less_than, Key (I _), Const_int _))
  | Formula.Not (Formula.Binop (Less_than_eq, Key (I _), Const_int _)) ->
      true
  | _ ->
      false

(** 
  [partition formula] partitions FORMULA into formulas 
  [SOLVABLE, UNSOLVABLE], where UNSOLVABLE is [None] if everything
  can be solved by IDL
*)
let partition_idl (formula : (bool, 'k) Formula.t) 
  : int list * int list =
  let rec aux index solvable unsolvable = function
    | [] ->
        (List.rev solvable, List.rev unsolvable)
    | clause :: rest ->
        if is_idl_clause clause then
          aux (index + 1) (index :: solvable) unsolvable rest
        else
          aux (index + 1) solvable (index :: unsolvable) rest
  in
  aux 0 [] [] (Formula.clauses_from formula)
;;

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
    |> Uid.Map.of_list
  in
  let n = 1 + Uid.Map.cardinal key_to_index + 1
  (* [0; x; y; z0] *)
  in
  let get_index x = Uid.Map.find x key_to_index in
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
  n, edges, key_to_index

exception Graph_disconnected of int

let bellman_ford 
  ~(src : int)
  (n : int)
  (edges : (int * int * int) array) =
  let init = (
    Array.init n (fun i -> if i = src then 0 else Int.max_int),
    Array.init n (fun _ : int option -> None)
  ) in
  let vertices = Array.init n (fun i -> i) in
  let distance, predecessor = Array.fold_left (fun (distance, predecessor) i -> 
    if i = n - 1 
    then distance, predecessor
    else 
      edges
      |> Array.fold_left 
        (fun (distance, predecessor) (u, v, w) ->
          match distance.(u), distance.(v) with
          | du, _ when du = Int.max_int -> (distance, predecessor)
          | du, dv when dv = Int.max_int ->
            let () =
              distance.(v) <- du + w;
              predecessor.(v) <- Some u;
            in
            (distance, predecessor)
          | du, dv -> 
            let () =
              if du + w < dv then
                distance.(v) <- du + w;
              predecessor.(v) <- Some u;
            in
            (distance, predecessor)
        )
        (distance, predecessor)
  ) init vertices
  in
  let rec find_cycle_start i =
    if i >= Array.length edges then None
    else
      let (u, v, w) = edges.(i) in
      match distance.(u), distance.(v) with
      | du, _ when du = Int.max_int -> raise (Graph_disconnected u)
      | _, dv when dv = Int.max_int -> raise (Graph_disconnected v)
      | du, dv when du + w < dv -> Some v
      | _ -> find_cycle_start (i + 1)
  in
  match find_cycle_start 0 with
  | None -> `No_negative_cycle (distance, predecessor)
  | Some vertex ->
    let rec move_back x i =
      if i = 0 then x
      else match predecessor.(x) with
        | None -> x
        | Some parent -> move_back parent (i - 1)
    in
    let cycle_vertex = move_back vertex n in
    let rec collect_cycle curr acc =
      if List.mem curr acc then 
        curr :: acc
      else
        match predecessor.(curr) with
        | None -> curr :: acc
        | Some parent -> collect_cycle parent (curr :: acc)
    in
    `Negative_cycle (collect_cycle cycle_vertex [])
;;

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
let solve_int_diff (f : (bool, 'k) Formula.t) : 'k Solution.t =
  f
  |> extract_idl
  |> normalize
  |> fun (vertices, edges, key_to_index) -> bellman_ford vertices edges ~src:0
  |> function
  | `Negative_cycle _ -> Solution.Unsat
  | `No_negative_cycle (distances, _) ->
    let n = Array.length distances in 
    let offset = distances.(n - 1) in
    let keys = (
      key_to_index
      |> Uid.Map.to_list
      |> List.map (fun (key, _) -> key)
    ) in
    let model = Model.of_local
      keys
      ~lookup:(fun symbol_key ->
        match Uid.Map.find_opt symbol_key key_to_index with
        | None -> None
        | Some i ->
          Some (-1 * (distances.(i) - offset))
      )
    in
    Solution.Sat model
;;

(** [simplify solve expr] drops redundant inequalities from EXPR before SOLVE calls it 
*)
let simplify : 'k Formula.simplifier = fun next expr ->
  expr
  |> rewrite
  |> next

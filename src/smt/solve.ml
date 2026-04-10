open Utils

module type SOLVABLE = sig
  include Formula.S

  val solve : (bool, 'k) t -> 'k Solution.t
end

type 'k solver = (bool, 'k) Formula.t -> 'k Solution.t
type 'k simplifier = 'k solver -> 'k solver

let direct_solve (module X : SOLVABLE) : 'k solver = fun e ->
  X.solve (Formula.transform (module X) e)

(*
  First attempts to solve with a few heuristics, and then calls the solver.
  This simply special-cases on some common formulas. It also extracts out
  constant assignments (variable = constant).

  Since the `binop` function in Formula turns greater-thans into less-thans, we
  don't handle any greater-than in the cases below--it will never happen since
  the user can only construct formulas with the smart constructors.
  Similarly, we will not get "not" of an inequality operator.

  As more simplifiers are added, we could instead name this after implied
  concretization.
*)
let rec propagate_constants : 'k simplifier = fun solve expr ->
  let assign i k = Solution.Sat (Model.singleton i k) in
  (* Hand-write a lot of special cases for single formulas *)
  match expr with
  | Const_bool false -> Unsat
  | Const_bool true -> Sat Model.empty
  | Key k ->
    assign true k
  | Not Key k ->
    assign false k
  | Not (Binop (Equal, Key k, Const_int i)) ->
    assign (if i = 0 then 1 else 0) k
  | Binop ((Equal | Less_than_eq), Key (I _ as k), Const_int i)
  | Binop ((Equal | Less_than_eq), Const_int i, Key (I _ as k)) ->
    assign i k
  | Binop (Less_than, Key k, Const_int i) ->
    assign (i - 1) k
  | Binop (Less_than, Const_int i, Key k) ->
    assign (i + 1) k
  | Binop (Less_than, Key (I _ as k), Key (I _ as k'))
  | Binop (Less_than_eq, Key (I _ as k), Key (I _ as k')) ->
    Solution.merge (assign 0 k) (assign 1 k')
  | Binop (Equal, Key k, Key k') ->
    begin match k, k' with
    | I _, I _ -> Solution.merge (assign 0 k) (assign 0 k')
    | B _, B _ -> Solution.merge (assign true k) (assign true k')
    end
  | Not Binop (Equal, Key k, Key k') ->
    begin match k, k' with
    | I _, I _ -> Solution.merge (assign 0 k) (assign 1 k')
    | B _, B _ -> Solution.merge (assign true k) (assign false k')
    end
  | And e_ls ->
    (*
      If there is any (key = int) formula, then we can subst it through, for it
      is an "implied concretization".
      This idea originates with KLEE (https://dl.acm.org/doi/abs/10.5555/1855741.1855756)
      from Section 3.3, paragraph _Constraint Set Simplification_.
    *)
    let find (e : ('a, 'k) Formula.t) : (const:int * (int, 'k) Symbol.t) option =
      match e with
      | Binop (Equal, Key k, Const_int const) -> Some (~const, k)
      | _ -> None
    in
    begin match List.find_map find e_ls with
    | Some (~const, k) ->
      let reduced_expr = Formula.and_ (List.map (Formula.subst const k) e_ls) in
      Solution.merge (propagate_constants solve reduced_expr) (assign const k)
    | None ->
      solve expr
    end
  | _ ->
    solve expr

type int_bound = {
  lower : int option;
  upper : int option;
  nots : int list;
}

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

(** TODO: Port over `rewrite` + friends here. *)
let bounds_rewrite : 'k simplifier = fun solve expr ->
  let rec loop_over 
    (bounds_state : (Uid.t * int_bound) list)
    (rest : (bool, 'k) Formula.t list) =
    function
    | Formula.Not (Formula.Binop (Binop.Equal, Const_int c, Key (I x)))
    | Not (Binop (Equal, Key (I x), Const_int c))
    | Binop (Not_equal, Const_int c, Key (I x))
    | Binop (Not_equal, Key (I x), Const_int c) -> (
      append_neq x c bounds_state, rest
    )
    | Binop (Less_than_eq, Const_int c1, rhs) -> 
      loop_over bounds_state rest (
        Formula.binop Greater_than_eq rhs (Formula.const_int c1)
      )
    | Binop (Less_than, Const_int c1, rhs) ->
      loop_over bounds_state rest (
        Formula.binop Greater_than rhs (Formula.const_int c1)
      )
    | Binop (Greater_than_eq, Const_int c1, rhs) ->
      loop_over bounds_state rest (
        Formula.binop Less_than_eq rhs (Formula.const_int c1)
      )
    | Binop (Greater_than, Const_int c1, rhs) ->
      loop_over bounds_state rest (
        Formula.binop Less_than rhs (Formula.const_int c1)
      )
    | Not (Binop (Less_than, a, b)) ->
      loop_over bounds_state rest (
        Formula.binop Greater_than_eq a b
      )
    | Not (Binop (Less_than_eq, a, b)) ->
      loop_over bounds_state rest (
        Formula.binop Greater_than a b
      )
    | Not (Binop (Greater_than, a, b)) ->
      loop_over bounds_state rest (
        Formula.binop Less_than_eq a b
      )
    | Not (Binop (Greater_than_eq, a, b)) ->
      loop_over bounds_state rest (
        Formula.binop Less_than a b
      )
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
                update_bounds 
                  x 
                  (fun b -> {
                    b with upper = Some (
                      match b.upper with
                      | None -> c
                      | Some u -> min u c
                    )
                  })
                  bounds_state
              )
            | Less_than -> (
                update_bounds
                  x
                  (fun b -> { 
                    b with upper = Some (
                      match b.upper with
                      | None -> c - 1
                      | Some u -> min u (c - 1)
                    ) 
                  })
                  bounds_state
              )
            | Greater_than_eq -> (
                update_bounds 
                  x 
                  (fun b -> {
                    b with lower = Some (
                      match b.lower with
                      | None -> c
                      | Some l -> max l c
                    )
                  })
                  bounds_state
              )
            | Greater_than -> (
                update_bounds
                  x
                  (fun b -> {
                    b with lower = Some (
                      match b.lower with
                      | None -> c + 1
                      | Some l -> max l (c + 1)
                    )
                  })
                  bounds_state
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
  solve expr

(** TODO: Port over `bellman_ford` + friends here. *)
let integer_difference : 'k simplifier = fun solve expr ->
  solve expr

(*
  Right-associative simplifier composition.
  E.g. this simplifier
    simpl1 @> simpl2 @> simpl3
  is equivalent to
    simpl1 @> (simpl2 @> simpl3)
  which we can see does simpl1 as a pre-pass to the composition of simpl2
  and simpl3. Hence when given a solver, this first simplifies with simpl1,
  then with simpl2, and finally with simpl3 before calling the solver.
*)
let (@>) : 'k simplifier -> 'k simplifier -> 'k simplifier =
  fun f g ->
    fun solve ->
      g (f solve)

(** TODO: Replace direct_solve with concolic/loop.ml *)
let main_solve (module Oracle : SOLVABLE) : 'k solver =
  let pipeline = bounds_rewrite
  @> propagate_constants
  @> integer_difference 
  in
  pipeline (direct_solve (module Oracle))


open Utils

type 'k atom =
  (** A ['k atom] captures all structs that are boolean in value for a formula with 'k keys *)
  | Bool_key of (bool, 'k) Symbol.t
  | Predicate : ('a * 'a * bool) Binop.t * ('a, 'k) Formula.t * ('a, 'k) Formula.t -> 'k atom

type 'k literal =
  (** A ['k literal] is either an SMT ['k atom] or the negation NEG of the atom *)
  | Pos of 'k atom
  | Neg of 'k atom

type 'k t_solution =
  (** A ['k t_solution] is a domain specific theory solution 'instantiated'
      by the parent ['k] formula key *)
  | Theory_sat of 'k Model.t
  | Theory_unsat of 'k literal list

type 'k t_solver = 'k literal list -> 'k t_solution
(** A ['k t_solver] accepts a list implied to be in a conjunction and returns its domain specific ['k t_solution] *)

type 'k assumption =
  { lit : 'k literal
  ; reason : 'k literal list
  }

let to_solution (theory : 'k t_solution) : 'k Solution.t =
  match theory with
  | Theory_unsat _ -> Unsat
  | Theory_sat model -> Sat model

let from_smt_atom (atom : (bool, 'k) Formula.t) : 'k atom =
  match atom with
  | Formula.Key key -> Bool_key key
  | Formula.Binop (op, left, right) -> Predicate (op, left, right)
  | Formula.Not _ | Formula.And _ | Formula.Const_bool _ ->
    failwith 
      (Printf.sprintf "[Theory.from_smt_atom] that's not a Key or a Binop: %s"
        (Formula.to_string ~key:Model.prefix_key atom))

let from_smt_literal (lit : (bool, 'k) Formula.t) : 'k literal =
  match lit with
  | Formula.Not inner -> Neg (from_smt_atom inner)
  | inner -> Pos (from_smt_atom inner)

let from_smt_clause (clause : (bool, 'k) Formula.t list) : 'k literal list =
  List.map from_smt_literal clause

let from_smt_formula (form : (bool, 'k) Formula.t list) : 'k literal list list =
  form
  |> List.map Formula.disjuncts_from_clause
  |> List.map from_smt_clause

(** [find_unsat_cores t_solutions] filters for Theory_unsat solutions over T_SOLUTIONS and maps out their conflict clause *)
let find_unsat_cores (t_solutions : 'k t_solution list) =
  List.filter_map
    (function
      | Theory_unsat core -> Some core
      | Theory_sat _ -> None)
    t_solutions

let original_assumptions (lits : 'k literal list) : 'k assumption list =
  List.map (fun lit -> { lit; reason = [lit] }) lits

let assumption_lits (assumptions : 'k assumption list) : 'k literal list =
  List.map (fun a -> a.lit) assumptions

let explain_lit (assumptions : 'k assumption list) (lit : 'k literal)
  : 'k literal list =
  match List.find_opt (fun a -> a.lit = lit) assumptions with
  | Some a -> a.reason
  | None -> [lit]

let explain_core (assumptions : 'k assumption list) (core : 'k literal list)
  : 'k literal list =
  core
  |> List.concat_map (explain_lit assumptions)
  |> List.sort_uniq compare

module Shared = struct
  type t =
    | Int_var of Uid.t
    | Bool_var of Uid.t
    | Int_const of int
    | Bool_const of bool

  let compare = compare

  let to_string ~(key : Model.key -> string) = function
  | Int_var uid -> key (Model.Int_key uid)
  | Bool_var uid -> key (Model.Bool_key uid)
  | Int_const i -> string_of_int i
  | Bool_const b -> string_of_bool b

  let from_formula : type a k. (a, k) Formula.t -> t option =
    function
    | Formula.Key (Symbol.I uid) -> Some (Int_var uid)
    | Formula.Key (Symbol.B uid) -> Some (Bool_var uid)
    | Formula.Const_int i -> Some (Int_const i)
    | Formula.Const_bool b -> Some (Bool_const b)
    | _ -> None
end

module SharedMap = Map.Make (Shared)

module SharedSet = Set.Make (Shared)

module type THEORY = sig
  val accepts : 'k literal -> bool

  val solve : 'k literal list -> 'k t_solution

  val implied_equalities :
    'k literal list ->
    (Shared.t * Shared.t) list

  val disequalities :
    'k literal list ->
    (Shared.t * Shared.t * 'k literal) list
end

let eq_lit_from_shared_pair : type k.
  Shared.t * Shared.t ->
  k literal option =
  function
  | Int_var x, Int_var y ->
      Some
        (Pos
           (Predicate
              (Equal,
               Formula.symbol (I x),
               Formula.symbol (I y))))

  | Int_var x, Int_const c
  | Int_const c, Int_var x ->
      Some
        (Pos
           (Predicate
              (Binop.Equal,
               Formula.symbol (I x),
               Formula.const_int c)))

  | Bool_var x, Bool_var y ->
      Some
        (Pos
           (Predicate
              (Binop.Equal,
               Formula.symbol (B x),
               Formula.symbol (B y))))

  | Bool_var x, Bool_const b
  | Bool_const b, Bool_var x ->
      Some
        (Pos
           (Predicate
              (Binop.Equal,
               Formula.symbol (Symbol.B x),
               Formula.const_bool b)))

  | Int_const a, Int_const b when a = b -> None
  | Bool_const a, Bool_const b when Bool.equal a b -> None

  | _ -> None

let normalize_pair (a, b) =
  if Shared.compare a b <= 0 then (a, b) else (b, a)

let dedup_pairs pairs =
  pairs
  |> List.map normalize_pair
  |> List.sort_uniq compare

let rec propagate_equalities
  (theories : (module THEORY) list)
  (assumptions : 'k assumption list)
  (known_eqs : (Shared.t * Shared.t) list)
  : 'k assumption list * (Shared.t * Shared.t) list =
  let lits = assumption_lits assumptions
  in
  let new_eqs =
    theories
    |> List.concat_map (fun (module T : THEORY) ->
        let local_lits = List.filter T.accepts lits in
        T.implied_equalities local_lits)
    |> dedup_pairs
  in
  let unseen =
    List.filter
      (fun eq -> not (List.mem eq known_eqs))
      new_eqs
  in
  if unseen = [] then assumptions, known_eqs
  else
    let new_assumptions =
      unseen
      |> List.filter_map (fun pair ->
        match eq_lit_from_shared_pair pair with
        | None -> None
        | Some lit ->
            Some
              { lit
              ; reason = lits
              })
    in
    propagate_equalities
      theories
      (new_assumptions @ assumptions)
      (unseen @ known_eqs)

let find_disequality_conflict theories lits known_eqs =
  theories
  |> List.find_map (fun (module T : THEORY) ->
       let local_lits = List.filter T.accepts lits in
       T.disequalities local_lits
       |> List.find_map (fun (l, r, original_lit) ->
            if List.mem (normalize_pair (l, r)) known_eqs then
              Some original_lit
            else
              None))

let solve_each (theories : (module THEORY) list) (assumptions : 'k assumption list) =
  let lits = assumption_lits assumptions in
  let rec loop models = function
    | [] -> Theory_sat (List.fold_left Model.merge Model.empty models)
    | (_i, (module T : THEORY)) :: rest ->
      let local_lits = List.filter T.accepts lits in
      match T.solve local_lits with
      | Theory_sat model -> loop (model :: models) rest
      | Theory_unsat core ->
        let explained = explain_core assumptions core
        in Theory_unsat explained
  in
  theories
  |> List.mapi (fun i theory -> i, theory)
  |> loop []

(** [combined theories] accepts a THEORIES list of domain-specific solvers
    and runs the Nelson Oppen merge algorithm against them to return 1 theory solver *)
let combine (theories : (module THEORY) list) : 'k t_solver =
  fun (lits : 'k literal list) ->
    let assumptions, known_eqs =
      propagate_equalities theories (original_assumptions lits) []
    in
    let propagated_lits = assumption_lits assumptions in
    match solve_each theories assumptions with
    | Theory_sat model ->
      begin match find_disequality_conflict theories propagated_lits known_eqs with
      | Some _ -> Theory_unsat lits
      | None -> Theory_sat model
      end
    | ts -> ts

(** [find_shared_variables ~accepts formula] finds the shared variables between the 
    subformulae that each accept callback in ACCEPTS returns [true] for in FORMULA *)
let find_shared_variables
  ~(accepts : ('k literal -> bool) list)
  (formula : 'k literal list list)
  : Shared.t list =
  let is_variable = function
    | Shared.Int_var _
    | Shared.Bool_var _ -> true
    | Shared.Int_const _
    | Shared.Bool_const _ -> false
  in
  let shared_terms_from_lit (lit : 'k literal) =
    let shared_terms_from_atom : type a. a atom -> Shared.t list =
      function
      | Bool_key (Symbol.B uid) -> [ Shared.Bool_var uid ]
      | Predicate (_, left, right) ->
          [ Shared.from_formula left
          ; Shared.from_formula right
          ]
          |> List.filter_map Fun.id
    in
    match lit with
    | Pos atom
    | Neg atom -> shared_terms_from_atom atom
  in
  let lits = List.flatten formula in
  let terms_for accepts_one =
    lits
    |> List.filter accepts_one
    |> List.concat_map shared_terms_from_lit
    |> List.filter is_variable
    |> SharedSet.of_list
  in

  let count_term_occ acc set =
    SharedSet.fold
      (fun term acc ->
        let old =
          match SharedMap.find_opt term acc with
          | Some n -> n
          | None -> 0
        in
        SharedMap.add term (old + 1) acc)
      set
      acc
  in
  let term_sets = List.map terms_for accepts in
  let counts =
    List.fold_left count_term_occ SharedMap.empty term_sets
  in
  counts
  |> SharedMap.to_seq
  |> Seq.filter_map
       (fun (term, count) ->
         if count >= 2 then Some term else None)
  |> List.of_seq

let interface_equalities
  ~(accepts : ('k literal -> bool) list)
  (formula : 'k literal list list)
  : (Shared.t * Shared.t) list =
  List_utils.combination2 @@ find_shared_variables ~accepts formula

let interface
  ~(accepts : ('k literal -> bool) list)
  (formula : 'k literal list list)
  : 'k literal list =
  let pairs = interface_equalities ~accepts formula in
  List.filter_map eq_lit_from_shared_pair pairs

let is_positive_interface_equality : 'k literal -> bool =
  function
  | Pos (Predicate (Binop.Equal, left, right)) ->
      begin match
        Shared.from_formula left,
        Shared.from_formula right
      with
      | Some _, Some _ -> true
      | _ -> false
      end
  | _ ->
      false

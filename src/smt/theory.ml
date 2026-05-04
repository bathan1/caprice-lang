open Utils

type 'k atom =
  (** An SMT atom is either a BOOL_KEY (bool literal) 
      or a binary op that returns a bool. *)
  | Bool_key of (bool, 'k) Symbol.t
  | Predicate : ('a * 'a * bool) Binop.t * ('a, 'k) Formula.t * ('a, 'k) Formula.t -> 'k atom

type 'k literal =
  (** An SMT literal is either an SMT [atom] or the negation NEG of the atom *)
  | Pos of 'k atom
  | Neg of 'k atom

type 'k t_solution =
  | Theory_sat of 'k Model.t
  | Theory_unsat of 'k literal list
  | Theory_unknown

type 'k assumption =
  { lit : 'k literal
  ; reason : 'k literal list
  }

let original_assumptions (lits : 'k literal list) : 'k assumption list =
  List.map
    (fun lit -> { lit; reason = [lit] })
    lits

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

let key =
  function
  | Model.Int_key k -> "I" ^ (Int.to_string @@ Utils.Uid.to_int k)
  | Model.Bool_key k -> "B" ^ (Int.to_string @@ Utils.Uid.to_int k)

let atom_to_string (atom : 'k atom) : string =
  let uid uid = Int.to_string (Utils.Uid.to_int uid) in
  match atom with
  | Bool_key (B id) -> Printf.sprintf "B%s" (uid id)
  | Predicate (binop, left, right) ->
    Printf.sprintf "%s %s %s"
    (Formula.to_string left ~key)
    (Binop.to_string binop)
    (Formula.to_string right ~key)

let literal_to_string (lit : 'k literal) : string =
  Printf.sprintf "%s"
    (match lit with
     | Pos atom -> atom_to_string atom
     | Neg atom -> "~" ^ atom_to_string atom)

let clause_to_string (clause : 'k literal list) : string =
  Printf.sprintf "(%s)"
    (Utils.List_utils.join ~sep:", " literal_to_string clause)

let formula_to_string (formula : 'k literal list list) : string =
  Printf.sprintf "[%s]"
    (Utils.List_utils.join ~sep:", " clause_to_string formula)

let unit_literals_to_formula_string (unit_literals : 'k literal list) : string =
  Printf.sprintf "[%s]"
    (Utils.List_utils.join ~sep:", " literal_to_string unit_literals)

let theory_solution_to_string
  (type k)
  ~key
  (solution : k t_solution)
  : string =
  match solution with
  | Theory_unknown -> "T_UNKNOWN"
  | Theory_sat model -> Printf.sprintf "T_SAT %s" (Model.to_string ~key model)
  | Theory_unsat core_clause -> Printf.sprintf "T_UNSAT %s" (clause_to_string core_clause)

let to_solution (theory : 'k t_solution) : 'k Solution.t =
  match theory with
  | Theory_unknown -> Unknown
  | Theory_unsat _ -> Unsat
  | Theory_sat model -> Sat model

type 'k t_solver = 'k literal list -> 'k t_solution

let from_smt_atom (atom : (bool, 'k) Formula.t) : 'k atom =
  match atom with
  | Formula.Key key -> Bool_key key
  | Formula.Binop (op, left, right) -> Predicate (op, left, right)
  | Formula.Not _ | Formula.And _ | Formula.Const_bool _ ->
    failwith 
      (Printf.sprintf "[Theory.from_smt_atom] that's not a Key or a Binop: %s"
        (Formula.to_string ~key atom))

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

module Shared = struct
  type t =
    | Int_var of Uid.t
    | Bool_var of Uid.t
    | Int_const of int
    | Bool_const of bool

  let compare = compare

  let to_string = function
    | Int_var uid -> Int.to_string @@ Uid.to_int uid
    | Bool_var uid -> Int.to_string @@ Uid.to_int uid
    | Int_const i -> string_of_int i
    | Bool_const b -> string_of_bool b

  let from_formula : type a k. (a, k) Formula.t -> t option =
    function
    | Formula.Key (Symbol.I uid) ->
        Some (Int_var uid)

    | Formula.Key (Symbol.B uid) ->
        Some (Bool_var uid)

    | Formula.Const_int i ->
        Some (Int_const i)

    | Formula.Const_bool b ->
        Some (Bool_const b)

    | _ ->
        None
end

module SharedMap = Map.Make (Shared)
module SharedSet = Set.Make (Shared)

module type THEORY = sig
  val owns : 'k literal -> bool

  val solve : 'k literal list -> 'k t_solution

  val implied_equalities :
    'k literal list ->
    (Shared.t * Shared.t) list

  val disequalities :
    'k literal list ->
    (Shared.t * Shared.t * 'k literal) list
end

let eq_lit_of_shared_pair : type k.
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

let rec propagate_equalities theories assumptions known_eqs =
  let lits =
    assumption_lits assumptions
  in

  let new_eqs =
    theories
    |> List.concat_map (fun (module T : THEORY) ->
         let local_lits = List.filter T.owns lits in
         T.implied_equalities local_lits)
    |> dedup_pairs
  in

  let unseen =
    List.filter
      (fun eq -> not (List.mem eq known_eqs))
      new_eqs
  in

  if unseen = [] then
    assumptions, known_eqs
  else
    let new_assumptions =
      unseen
      |> List.filter_map (fun pair ->
           match eq_lit_of_shared_pair pair with
           | None ->
               None

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
       let local_lits = List.filter T.owns lits in
       T.disequalities local_lits
       |> List.find_map (fun (l, r, original_lit) ->
            if List.mem (normalize_pair (l, r)) known_eqs then
              Some original_lit
            else
              None))

let solve_each_theory theories assumptions =
  let lits =
    assumption_lits assumptions
  in
  let rec loop models = function
    | [] -> Theory_sat (List.fold_left Model.merge Model.empty models)
    | (_i, (module T : THEORY)) :: rest ->
        let local_lits =
          List.filter T.owns lits
        in
        match T.solve local_lits with
        | Theory_sat model -> loop (model :: models) rest
        | Theory_unsat core ->
          let explained =
            explain_core assumptions core
          in
          Theory_unsat explained
        | Theory_unknown -> Theory_unknown
  in

  theories
  |> List.mapi (fun i theory -> i, theory)
  |> loop []

let combine theories : 'k t_solver =
  fun lits ->
    let assumptions, known_eqs =
      propagate_equalities theories (original_assumptions lits) []
    in
    let propagated_lits =
      assumption_lits assumptions
    in
    match solve_each_theory theories assumptions with
    | Theory_sat model ->
      begin match find_disequality_conflict theories propagated_lits known_eqs with
      | Some _ -> Theory_unsat lits
      | None -> Theory_sat model
      end
    | ts -> ts

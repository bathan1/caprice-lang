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

type 'k solver = 'k literal list -> 'k t_solution

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


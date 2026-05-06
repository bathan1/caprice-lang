open Formula

let value_opt (x : 'a) (model : literal list) : literal option =
  List.find_opt (fun lit -> atom_from_literal lit = x) model

let (#::) (x : 'a) (xs : ('a list) option) : ('a list) option =
  match xs with
  | None -> None
  | Some xs' -> Some (x :: xs')

(** [use_clause model ~clause] uses the literal values from MODEL in CLAUSE 
    and returns an option that is one of the following, depending on the inputs:

    - [None] means we found a matching literal between MODEL and CLAUSE, implying CLAUSE is true
    - [Some nonempty] means we haven't found a match yet but there are remaining literals in [nonempty] to match
    - [Some []] means no matching literal pair could be found, implying CLAUSE is falsified *)
let rec use_clause (clause : literal list) (model : literal list) : literal list option =
  match clause with
  | [] -> Some [] (* then we couldn't find a single true clause *)
  | lit :: clause' ->
    match value_opt (atom_from_literal lit) model with
    | None -> lit #:: (use_clause clause' model)
    | Some lit' ->
      if lit = lit' then None (* *)
      else use_clause clause' model

(** [use model ~form] uses the literal values from MODEL across
    all clauses in FORM and spits out the resulting formula *)
let rec use (formula : Formula.formula) (model : literal list) : Formula.formula =
  match formula with
  | [] -> []
  | clause :: form' -> 
    match use_clause clause model with
    | None -> use form' model
    | Some clause' -> clause' :: (use form' model)

(** [is_tautology formula model] *)
let is_tautology (formula : Formula.formula) (model : literal list) : bool =
  Formula.is_tautology (use formula model)

let pp_model ~uid fmt (m : literal list) =
  List.iter (Format.fprintf fmt "%a " (pp_literal ~uid)) m

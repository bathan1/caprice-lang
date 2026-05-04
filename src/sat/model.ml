open Formula

let value_opt (x : 'a) (model : literal list) : literal option =
  List.find_opt (fun lit -> key_from_lit lit = x) model

let (#::) (x : 'a) (xs : ('a list) option) : ('a list) option =
  match xs with
  | None -> None
  | Some xs' -> Some (x :: xs')

(** [use_clause model ~clause] uses the literal values from MODEL in CLAUSE 
    and returns an option that is one of the following, depending on the inputs:

    - [None] means we found a matching literal between MODEL and CLAUSE, implying CLAUSE is true
    - [Some nonempty] means we haven't found a match yet but there are remaining literals in [nonempty] to match
    - [Some []] means no matching literal pair could be found, implying CLAUSE is falsified *)
let rec use_clause (model : literal list) ~(clause : literal list) : literal list option =
  match clause with
  | [] -> Some [] (* then we couldn't find a single true clause *)
  | lit :: clause' ->
    match value_opt (key_from_lit lit) model with
    | None -> lit #:: (use_clause model ~clause:clause')
    | Some lit' ->
      if lit = lit' then None (* *)
      else use_clause model ~clause:clause'

(** [use model ~form] uses the literal values from MODEL across
    all clauses in FORM and spits out the resulting formula *)
let rec use (model : literal list) ~(form : Formula.t) : Formula.t =
  match form with
  | [] -> []
  | clause :: form' -> 
    match use_clause model ~clause with
    | None -> use model ~form:form'
    | Some clause' -> clause' :: (use model ~form:form')

let is_tautology (model : literal list) ~(form : Formula.t) : bool =
  Formula.is_tautology (use model ~form)

let pp_model ppf (m : literal list) =
  List.iter (Format.fprintf ppf "%a " pp_literal) m

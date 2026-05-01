open Formula

type t = literal list

let value_opt (x : 'a) (model : t) : literal option =
  List.find_opt (fun lit -> key lit = x) model

let (#::) (x : 'a) (xs : ('a list) option) : ('a list) option =
  match xs with
  | None -> None
  | Some xs' -> Some (x :: xs')

(** [use_clause model ~clause] uses the literal values from MODEL in CLAUSE 
    and returns an option that is one of the following, depending on the inputs:

    - [None] means we found a matching literal between MODEL and CLAUSE, implying CLAUSE is true
    - [Some nonempty] means we haven't found a match yet but there are remaining literals in [nonempty] to match
    - [Some []] means no matching literal pair could be found, implying CLAUSE is falsified *)
let rec use_clause (model : t) ~(clause : clause) : clause option =
  match clause with
  | [] -> Some [] (* then we couldn't find a single true clause *)
  | lit :: clause' ->
    match value_opt (key lit) model with
    | None -> lit #:: (use_clause model ~clause:clause')
    | Some lit' ->
      if lit = lit' then None (* *)
      else use_clause model ~clause:clause'

(** [use model form] uses the literal values from MODEL across
    all clauses in FORM and spits out the resulting formula *)
let rec use (model : t) (form : Formula.t) : Formula.t =
  match form with
  | [] -> []
  | clause :: form' -> 
    match use_clause model ~clause with
    | None -> use model form'
    | Some clause' -> clause' :: (use model form')

let is_tautology (form : Formula.t) (model : t) : bool =
  Formula.is_tautology (use model form)

let pp_model ppf (m : t) =
  List.iter (Printf.fprintf ppf "%a " pp_literal) m

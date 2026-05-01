open Formula

type t = literal list

let value_opt (x : 'a) (model : t) : literal option =
  List.find_opt (fun lit -> key lit = x) model

let (#::) (x : 'a) (xs : ('a list) option) : ('a list) option =
  match xs with
  | None -> None
  | Some xs' -> Some (x :: xs')

let rec use_clause (clause : clause) (model : t) : clause option =
  match clause with
  | [] -> Some []
  | lit :: clause' ->
    match value_opt (key lit) model with
    | None -> lit #:: (use_clause clause' model)
    | Some lit' ->
      if lit = lit' then None
      else use_clause clause' model

let rec use (form : Formula.t) (model : t) : Formula.t =
  match form with
  | [] -> []
  | clause :: form' -> 
    match use_clause clause model with
    | None -> use form' model
    | Some clause' -> clause' :: (use form' model)

let is_tautology (form : Formula.t) (model : t) : bool =
  Formula.is_tautology (use form model)


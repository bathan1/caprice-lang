open Utils
open Utils.List_utils

type atom = Uid.t

type literal =
  | Pos of atom
  | Neg of atom

type t = literal list list

let negate (lit : literal) : literal =
  match lit with
  | Pos n -> Neg n
  | Neg n -> Pos n

let is_empty (clause : literal list) : bool =
  match clause with
  | [] -> true
  | _ -> false

let is_unit_clause (clause : literal list) : bool =
  match clause with
  | [_] -> true
  | _ -> false

let key (lit : literal) : atom = match lit with | Pos n | Neg n -> n

let find_free_variable (bound : atom list) (form : t) : atom option =
  form
  |> List.flatten
  |> List.find_opt (fun lit -> not (List.mem (key lit) bound))
  |> Option.map key

let is_tautology (form : t) : bool = form = []

let disjoin (clause1 : literal list) (clause2 : literal list) : literal list =
  List.fold_right (fun lit clause3 -> if (List.mem lit clause3) then clause3 else lit :: clause3) clause1 clause2

let conjoin1 (form : t) (clause : literal list) : t = clause :: form

let conjoin (forms : t list) : t = List.flatten forms

let resolve_pair (clause1 : literal list) (clause2 : literal list) =
  match find_pair (fun lit1 lit2 -> lit1 = negate lit2) clause1 clause2 with
  | None -> failwith "that's not resolvable!"
  | Some (l1, l2) -> disjoin (remove1 l1 clause1) (remove1 l2 clause2)

let pp_literal fd (lit : literal) : unit =
  Printf.fprintf fd "%s%d" (match lit with | Pos _ -> "" | Neg _ -> "~") (Uid.to_int (key lit))

let pp_clause fd (clause : literal list) : unit =
  let n = List.length clause in 
  List.iteri
    (fun i lit -> 
      if i < n - 1 then Printf.fprintf fd "(%a) " pp_literal lit
      else Printf.fprintf fd "(%a)" pp_literal lit)
    clause

let pp_formula fd (form : t) : unit =
  let n = List.length form in
  if (is_tautology form) then Printf.fprintf fd "true"
  else List.iteri 
    (fun i clause ->
      if i < n - 1 then (Printf.fprintf fd "(%a) " pp_clause) clause
      else (Printf.fprintf fd "(%a)" pp_clause) clause)
    form

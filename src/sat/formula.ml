open Utils
open Utils.List_utils

type literal =
  | Pos of Uid.t
  | Neg of Uid.t

type clause = literal list

type t = clause list

let negate (lit : literal) : literal =
  match lit with
  | Pos n -> Neg n
  | Neg n -> Pos n

let is_empty (c : clause) : bool =
  match c with
  | [] -> true
  | _ -> false

let is_unit_clause (c : clause) : bool =
  match c with
  | [_] -> true
  | _ -> false

let key (lit : literal) : Uid.t = match lit with | Pos n | Neg n -> n

let find_free_variable (bound : Uid.t list) (form : t) : Uid.t option =
  form
  |> List.flatten
  |> List.find_opt (fun lit -> not (List.mem (key lit) bound))
  |> Option.map key

let is_tautology (form : t) : bool = form = []

let disjoin (c1 : clause) (c2 : clause) : clause =
  List.fold_right (fun lit c3 -> if (List.mem lit c3) then c3 else lit :: c3) c1 c2

let conjoin1 (form : t) (c : clause) : clause list = c :: form

let conjoin (forms : t list) : t = List.flatten forms

let resolve_pair (c1 : clause) (c2 : clause) =
  match find_pair (fun x y -> x = negate y) c1 c2 with
  | None -> failwith "that's not resolvable!"
  | Some (l1, l2) -> disjoin (remove1 l1 c1) (remove1 l2 c2)

let pp_literal fd (lit : literal) : unit =
  Printf.fprintf fd "%s%d" (match lit with | Pos _ -> "" | Neg _ -> "~") (Uid.to_int (key lit))

let pp_clause fd (clause : clause) : unit =
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

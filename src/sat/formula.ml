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

let key_from_lit (lit : literal) : atom = match lit with | Pos n | Neg n -> n

let find_free_variable (bound : atom list) (form : t) : atom option =
  form
  |> List.flatten
  |> List.find_opt (fun lit -> not (List.mem (key_from_lit lit) bound))
  |> Option.map key_from_lit

let is_tautology (form : t) : bool = form = []

let disjoin (clause1 : literal list) (clause2 : literal list) : literal list =
  List.fold_right (fun lit clause3 -> if (List.mem lit clause3) then clause3 else lit :: clause3) clause1 clause2

let conjoin1 (form : t) (clause : literal list) : t = clause :: form

let conjoin (forms : t list) : t = List.flatten forms

let resolve_pair (clause1 : literal list) (clause2 : literal list) =
  match find_pair (fun lit1 lit2 -> lit1 = negate lit2) clause1 clause2 with
  | None -> failwith "that's not resolvable!"
  | Some (l1, l2) -> disjoin (remove1 l1 clause1) (remove1 l2 clause2)

let literal_to_string (lit : literal) : string =
  Printf.sprintf "%s%d"
    (match lit with | Pos _ -> "" | Neg _ -> "~")
    (Uid.to_int (key_from_lit lit))

let clause_to_string (clause : literal list) : string =
  let n = List.length clause in 
  Printf.sprintf "(%s)"
  (fst (List.fold_left
    (fun (acc, i) lit ->
      (acc ^ Printf.sprintf "%s%s"
        (literal_to_string lit)
        (if i < n - 1 then ", " else ""),
      i + 1)
    ) ("", 0) clause))

let to_string (formula : literal list list) : string =
  let n = List.length formula in
  Printf.sprintf "[%s]"
  (fst (List.fold_left
    (fun (acc, i) clause ->
      (acc ^ Printf.sprintf "%s%s"
        (clause_to_string clause)
        (if i < n - 1 then "," else "")),
      i + 1
    ) ("", 0) formula))

let pp_literal ~(uid : Uid.t -> string) fmt (lit : literal) : unit =
  let prefix =
    match lit with
    | Pos _ -> ""
    | Neg _ -> "~"
  in
  Format.fprintf fmt "%s%s" prefix (uid (key_from_lit lit))

let pp_clause ~(uid : Uid.t -> string) fmt (clause : literal list) : unit =
  match clause with
  | [lit] ->
      Format.fprintf fmt "@[%a@]" (pp_literal ~uid) lit
  | _ ->
      Format.fprintf fmt "(@[%a@])"
        (Format.pp_print_list
           ~pp_sep:(fun fmt () -> Format.fprintf fmt " v@ ")
           (pp_literal ~uid))
        clause

let pp_formula ~(uid : Uid.t -> string) fmt (form : t) : unit =
  if is_tautology form then
    Format.fprintf fmt "true"
  else
    Format.fprintf fmt "@[%a@]"
      (Format.pp_print_list
         ~pp_sep:(fun fmt () -> Format.fprintf fmt " ^@ ")
         (pp_clause ~uid))
      form

let print_literal ~uid lit =
  Format.printf "%a@." (pp_literal ~uid) lit

let print_clause ~uid clause =
  Format.printf "%a@." (pp_clause ~uid) clause

let print_formula ~uid form =
  Format.printf "%a@." (pp_formula ~uid) form

let uid_to_int_string (uid : Uid.t) : string =
  uid
  |> Uid.to_int
  |> Int.to_string

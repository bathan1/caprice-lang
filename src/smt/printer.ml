include Theory

let pp_atom ~key fmt (atom : 'k atom) : unit =
  match atom with
  | Bool_key (B id) ->
      Format.fprintf fmt "B%d" (Utils.Uid.to_int id)

  | Predicate (binop, left, right) ->
      Format.fprintf fmt "(%s %s %s)"
        (Formula.to_string left ~key)
        (Binop.to_string binop)
        (Formula.to_string right ~key)

let pp_literal ~key fmt (lit : 'k literal) : unit =
  match lit with
  | Pos atom ->
      Format.fprintf fmt "%a" (pp_atom ~key) atom
  | Neg atom ->
      Format.fprintf fmt "(not %a)" (pp_atom ~key) atom

let pp_clause ~key fmt (clause : 'k literal list) : unit =
  match clause with
  | [Pos _ as lit]
  | [Neg _ as lit] ->
      Format.fprintf fmt "@[%a@]" (pp_literal ~key) lit
  | _ ->
      Format.fprintf fmt "(@[%a@])"
        (Format.pp_print_list
           ~pp_sep:(fun fmt () -> Format.fprintf fmt " v@ ")
           (pp_literal ~key))
        clause

let pp_delim_literals ?(delim = "\n") ~key fmt (lits : 'k literal list) : unit =
  Format.fprintf fmt "@[%a@]"
    (Format.pp_print_list
       ~pp_sep:(fun fmt () -> Format.fprintf fmt "%s" delim)
       (pp_literal ~key))
    lits

let print_delim_literals ?delim ~key (lits : 'k literal list) : unit =
  Format.printf "%a@." (pp_delim_literals ?delim ~key) lits

let pp_unit_literals ~key fmt (lits : 'k literal list) : unit =
  Format.fprintf fmt "@[%a@]"
    (Format.pp_print_list
       ~pp_sep:(fun fmt () -> Format.fprintf fmt " ^@ ")
       (pp_literal ~key))
    lits

let pp_formula ~key fmt (formula : 'k literal list list) : unit =
  Format.fprintf fmt "@[%a@]"
    (Format.pp_print_list
       ~pp_sep:(fun fmt () -> Format.fprintf fmt " ^@ ")
       (pp_clause ~key))
    formula

let pp_t_solution
  (type k)
  ~(key : Model.key -> string)
  (fmt : Format.formatter)
  (solution : k theory_solution)
  : unit =
  match solution with
  | Theory_sat model ->
      Format.fprintf fmt "(T) SAT %s" (Model.to_string ~key model)
  | Theory_unsat core_lits ->
      Format.fprintf fmt "(T) UNSAT %a" (pp_unit_literals ~key) core_lits

let pp_shared ~uid fmt (var : Shared.t) =
  let value =
    match var with
    | Int_const v -> Int.to_string v
    | Bool_const v -> Bool.to_string v
    | Int_var uid_v
    | Bool_var uid_v -> uid uid_v
  in
  Format.fprintf fmt "%s" value

let print_shared ~uid (var : Shared.t) =
  Format.printf "%a@." (pp_shared ~uid) var

let print_atom ~key atom =
  Format.printf "%a@." (pp_atom ~key) atom

let print_literal ~key lit =
  Format.printf "%a@." (pp_literal ~key) lit

let print_unit_literals ~key lits =
  Format.printf "%a@." (pp_unit_literals ~key) lits

let print_clause ~key clause =
  Format.printf "%a@." (pp_clause ~key) clause

let print_formula ~key formula =
  Format.printf "%a@." (pp_formula ~key) formula

let print_t_solution ~key solution =
  Format.printf "%a@." (pp_t_solution ~key) solution

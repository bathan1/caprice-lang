include Theory

let pp_atom ~key fmt (atom : 'k atom) : unit =
  match atom with
  | Bool_key (B id) ->
      Format.fprintf fmt "B%d" (Utils.Uid.to_int id)

  | Predicate (binop, left, right) ->
      Format.fprintf fmt "%s %s %s"
        (Formula.to_string left ~key)
        (Binop.to_string binop)
        (Formula.to_string right ~key)

let pp_literal ~key fmt (lit : 'k literal) : unit =
  match lit with
  | Pos atom ->
      Format.fprintf fmt "%a" (pp_atom ~key) atom
  | Neg atom ->
      Format.fprintf fmt "not (%a)" (pp_atom ~key) atom

let pp_clause ~key fmt (clause : 'k literal list) : unit =
  Format.fprintf fmt "(@[%a@])"
    (Format.pp_print_list
       ~pp_sep:(fun fmt () -> Format.fprintf fmt " v@ ")
       (pp_literal ~key))
    clause

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
  (solution : k t_solution)
  : unit =
  match solution with
  | Theory_sat model ->
      Format.fprintf fmt "(T) SAT %s" (Model.to_string ~key model)
  | Theory_unsat core_clause ->
      Format.fprintf fmt "(T) UNSAT %a" (pp_clause ~key) core_clause

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

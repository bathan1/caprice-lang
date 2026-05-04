type 'k atom =
  (** An SMT atom is either a BOOL_KEY (bool literal) 
      or a binary op that returns a bool. *)
  | Bool_key of (bool, 'k) Symbol.t
  | Predicate : ('a * 'a * bool) Binop.t * ('a, 'k) Formula.t * ('a, 'k) Formula.t -> 'k atom

type 'k literal =
  (** An SMT literal is either an SMT [atom] or the negation NEG of the atom *)
  | Pos of 'k atom
  | Neg of 'k atom

type 'k solution = ('k, 'k literal list) Solution.theory_solution

type 'k solver = 'k literal list -> 'k solution

let from_smt_atom (atom : (bool, 'k) Formula.t) : 'k atom =
  match atom with
  | Formula.Key key -> Bool_key key
  | Formula.Binop (op, left, right) -> Predicate (op, left, right)
  | Formula.Not _ | Formula.And _ | Formula.Const_bool _ ->
    failwith 
      (Printf.sprintf "[Theory.from_smt_atom] that's not a Key or a Binop: %s"
        (Formula.to_string ~uid:Symbol.AsciiSymbol.to_string atom))

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

let atom_to_string (atom : 'k atom) : string =
  let uid uid = Int.to_string (Utils.Uid.to_int uid) in
  match atom with
  | Bool_key (B id) -> Printf.sprintf "B%s" (uid id)
  | Predicate (binop, left, right) ->
    Printf.sprintf "%s %s %s"
    (Formula.to_string left ~uid)
    (Binop.to_string binop)
    (Formula.to_string right ~uid)

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

let pp_atom fmt (atom : 'k atom) : unit =
  match atom with
  | Bool_key key ->
    Format.fprintf fmt "%a" Symbol.pp_symbol key

  | Predicate (binop, left, right) ->
    Format.fprintf
      fmt
      "%a"
      (Formula.pp_formula ~uid:(Symbol.AsciiSymbol.to_string))
      (Formula.binop binop left right)

let pp_literal
  (fmt : Format.formatter)
  (lit : 'k literal)
  : unit =
  match lit with
  | Pos atom ->
    Format.fprintf fmt "%a" pp_atom atom

  | Neg atom ->
    Format.fprintf fmt "~%a" pp_atom atom

let pp_clause
  (fmt : Format.formatter)
  (clause : 'k literal list)
  : unit =
  let n = List.length clause in
  List.iteri
    (fun i lit ->
      if i < n - 1 then
        Format.fprintf fmt "(%a) " pp_literal lit
      else
        Format.fprintf fmt "(%a)" pp_literal lit)
    clause

let pp_formula
  (fmt : Format.formatter)
  (form : 'k literal list list)
  : unit =
  let n = List.length form in
  List.iteri
    (fun i clause ->
      if i < n - 1 then
        Format.fprintf fmt "(%a) " pp_clause clause
      else
        Format.fprintf fmt "(%a)" pp_clause clause)
    form

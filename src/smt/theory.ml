open Utils

type 'k atom =
  (** A ['k atom] captures all structs that are boolean in value for a formula with 'k keys *)
  | Bool_key of (bool, 'k) Symbol.t
  | Predicate : ('a * 'a * bool) Binop.t * ('a, 'k) Formula.t * ('a, 'k) Formula.t -> 'k atom

type 'k literal =
  (** A ['k literal] is either an SMT ['k atom] or the negation NEG of the atom *)
  | Pos of 'k atom
  | Neg of 'k atom

type 'k theory_solution =
  (** A ['k theory_solution] is a domain specific theory solution 'instantiated'
      by the parent ['k] formula key *)
  | Theory_sat of 'k Model.t
  | Theory_unsat of 'k literal list
  | Theory_split of 'k literal list list

type 'k theory_solver = 'k literal list -> 'k theory_solution
(** A ['k theory_solver] accepts a list implied to be in a conjunction and returns its domain specific ['k t_solution] *)

type 'k assumption =
  { lit : 'k literal
  ; reason : 'k literal list
  }

module Shared = struct
  type t =
    | Int_var of Uid.t
    | Bool_var of Uid.t
    | Int_const of int
    | Bool_const of bool

  let compare = compare

  let to_string ~(key : Model.key -> string) = function
  | Int_var uid -> key (Model.Int_key uid)
  | Bool_var uid -> key (Model.Bool_key uid)
  | Int_const i -> string_of_int i
  | Bool_const b -> string_of_bool b

  let from_formula : type a k. (a, k) Formula.t -> t option =
    function
    | Formula.Key (Symbol.I uid) -> Some (Int_var uid)
    | Formula.Key (Symbol.B uid) -> Some (Bool_var uid)
    | Formula.Const_int i -> Some (Int_const i)
    | Formula.Const_bool b -> Some (Bool_const b)
    | _ -> None
end

module SharedMap = Map.Make (Shared)

module SharedSet = Set.Make (Shared)

module type THEORY = sig
  val tag : string
  (** For debug prints. Should be unique per theory *)

  val accepts : 'k literal -> bool
  (** [accepts lit] returns whether LIT is a valid literal for this theory's [solve] input. *)

  val solve : 'k literal list -> 'k theory_solution
  (** [solve lits] checks satisfiability of the conjunction of theory literals LITS *)

  val implied_equalities : 'k literal list -> (Shared.t * Shared.t) list
  (** [implied_equalities lits] returns equalities over shared terms that are entailed by LITS *)

  val disequalities : 'k literal list -> (Shared.t * Shared.t * 'k literal) list
  (** [disequalities lits] returns explicit disequalities over shared terms, paired with their source literal derived from LITS *)
end

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

let pp_theory_solution
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
  | Theory_split split -> Format.fprintf fmt "(T) SPLIT %a" (pp_formula ~key) split

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

let print_theory_solution ~key solution =
  Format.printf "%a@." (pp_theory_solution ~key) solution

let to_solution (theory : 'k theory_solution) : 'k Solution.t =
  match theory with
  | Theory_unsat _ -> Unsat
  | Theory_sat model -> Sat model
  | Theory_split _ -> Unknown

let from_smt_atom (atom : (bool, 'k) Formula.t) : 'k atom =
  match atom with
  | Formula.Key key -> Bool_key key
  | Formula.Binop (op, left, right) -> Predicate (op, left, right)
  | Formula.Not _ | Formula.And _ | Formula.Const_bool _ ->
    failwith 
      (Printf.sprintf "[Theory.from_smt_atom] that's not a Key or a Binop: %s"
        (Formula.to_string ~key:Model.prefix_key atom))

let from_smt_literal (lit : (bool, 'k) Formula.t) : 'k literal =
  match lit with
  | Formula.Not inner -> Neg (from_smt_atom inner)
  | inner -> Pos (from_smt_atom inner)

(** [from_smt_clause_like clause] maps each element in CLAUSE to their corresponding
    theory [literal]. This is just a [List.map] over a formula list and doesn't 
    care whether the list is meant to be interpreted as a disjunction or a conjunction 
    of unit clauses. That interpretation is up to the caller. *)
let from_smt_clause_like (clause : (bool, 'k) Formula.t list) : 'k literal list =
  List.map from_smt_literal clause

let from_smt_formula (form : (bool, 'k) Formula.t list) : 'k literal list list =
  form
  |> List.map Formula.disjuncts_from_clause
  |> List.map from_smt_clause_like

(** [find_unsat_cores t_solutions] filters for Theory_unsat solutions over T_SOLUTIONS and maps out their conflict clause *)
let find_unsat_cores (t_solutions : 'k theory_solution list) =
  List.filter_map
    (function
      | Theory_unsat core -> Some core
      | _ -> None)
    t_solutions

let eq_lit_from_shared_pair : type k.
  Shared.t * Shared.t ->
  k literal option =
  function
  | Int_var x, Int_var y ->
      Some
        (Pos
           (Predicate
              (Equal,
               Formula.symbol (I x),
               Formula.symbol (I y))))

  | Int_var x, Int_const c
  | Int_const c, Int_var x ->
      Some
        (Pos
           (Predicate
              (Binop.Equal,
               Formula.symbol (I x),
               Formula.const_int c)))

  | Bool_var x, Bool_var y ->
      Some
        (Pos
           (Predicate
              (Binop.Equal,
               Formula.symbol (B x),
               Formula.symbol (B y))))

  | Bool_var x, Bool_const b
  | Bool_const b, Bool_var x ->
      Some
        (Pos
           (Predicate
              (Binop.Equal,
               Formula.symbol (Symbol.B x),
               Formula.const_bool b)))

  | Int_const a, Int_const b when a = b -> None
  | Bool_const a, Bool_const b when Bool.equal a b -> None

  | _ -> None

let normalize_pair (a, b) =
  if Shared.compare a b <= 0 then (a, b) else (b, a)

let dedup_pairs pairs =
  pairs
  |> List.map normalize_pair
  |> List.sort_uniq compare

(** [literals_to_assumptions lits] maps each lit in LITS into their initial assumption item *)
let literals_to_assumptions (lits : 'k literal list) : 'k assumption list =
  List.map (fun lit -> { lit; reason = [lit] }) lits

let literals_from_assumptions (assumptions : 'k assumption list) : 'k literal list =
  List.map (fun a -> a.lit) assumptions

let print_shared_pair ~uid (l, r) =
  Format.printf "  %a = %a@."
    (pp_shared ~uid) l
    (pp_shared ~uid) r

let print_diseq ~uid ~key (l, r, lit) =
  Format.printf "  %a != %a    from %a@."
    (pp_shared ~uid) l
    (pp_shared ~uid) r
    (pp_literal ~key) lit

let print_assumptions ~key assumptions =
  Format.printf "Assumptions:@.";
  assumptions
  |> literals_from_assumptions
  |> List.iter (fun lit ->
       Format.printf "  %a@." (pp_literal ~key) lit)

let print_known_eqs ~uid known_eqs =
  Format.printf "Known equalities:@.";
  begin match known_eqs with
  | [] -> Format.printf "  <none>@."
  | _ -> List.iter (print_shared_pair ~uid) known_eqs
  end

let print_theory_inputs ~key assumptions =
  Format.printf "Theory inputs:@.";
  assumptions
  |> List.iteri (fun i assumption ->
       Format.printf "  Theory %d:@." i;
       begin match literals_from_assumptions [assumption] with
       | [] ->
           Format.printf "    <none>@."
       | lits ->
           lits
           |> List.iter (fun lit ->
                Format.printf "    %a@." (pp_literal ~key) lit)
       end)

let print_theory_implied_equalities ~uid theories propagated_lits =
  Format.printf "Theory implied equalities:@.";
  theories
  |> List.iteri (fun i (module T : THEORY) ->
       let owned = List.filter T.accepts propagated_lits in
       let eqs = T.implied_equalities owned in
       Format.printf "  Theory %d:@." i;
       begin match eqs with
       | [] -> Format.printf "    <none>@."
       | _ ->
           eqs
           |> List.iter (fun (l, r) ->
                Format.printf "    %a = %a@."
                  (pp_shared ~uid) l
                  (pp_shared ~uid) r)
       end)

let print_theory_disequalities ~uid ~key theories propagated_lits =
  Format.printf "Theory disequalities:@.";
  theories
  |> List.iteri (fun i (module T : THEORY) ->
       let owned = List.filter T.accepts propagated_lits in
       let diseqs = T.disequalities owned in
       Format.printf "  Theory %d:@." i;
       begin match diseqs with
       | [] -> Format.printf "    <none>@."
       | _ ->
           diseqs
           |> List.iter (fun diseq ->
                Format.printf "    ";
                print_diseq ~uid ~key diseq)
       end)

(** [eq_pair_from_lit lit] returns the terms from LIT that in a 2-tuple
    if they are in an [=] binop. Otherwise it returns None *)
let eq_pair_from_lit : type k. k literal -> (Shared.t * Shared.t) option =
  function
  | Pos (Predicate (Binop.Equal, left, right)) ->
      begin match Shared.from_formula left, Shared.from_formula right with
      | Some l, Some r -> Some (normalize_pair (l, r))
      | _ -> None
      end
  | _ -> None

let rec propagate_equalities
  (theories : (module THEORY) list)
  (assumptions : 'k assumption list)
  (known_eqs : (Shared.t * Shared.t) list)
  : 'k assumption list * (Shared.t * Shared.t) list =
  let lits = literals_from_assumptions assumptions in
  let existing_eqs =
    assumptions
    |> List.filter_map (fun a -> eq_pair_from_lit a.lit)
    |> dedup_pairs
  in
  let known_eqs = dedup_pairs (known_eqs @ existing_eqs)
  in
  let new_eqs =
    theories
    |> List.concat_map (fun (module TheorySolver : THEORY) ->
        let local_lits = List.filter TheorySolver.accepts lits in
        TheorySolver.implied_equalities local_lits)
    |> dedup_pairs
  in
  let unseen =
    List.filter
      (fun eq -> not (List.mem eq known_eqs))
      new_eqs
  in
  if unseen = [] then
    assumptions, known_eqs
  else
    let new_assumptions =
      unseen
      |> List.filter_map (fun pair ->
          match eq_lit_from_shared_pair pair with
          | None -> None
          | Some lit ->
              Some
                { lit
                ; reason = lits
                })
    in
    propagate_equalities
      theories
      (new_assumptions @ assumptions)
      (dedup_pairs (unseen @ known_eqs))

let find_disequality_conflict theories lits known_eqs =
  theories
  |> List.find_map (fun (module TheorySolver : THEORY) ->
       let local_lits = List.filter TheorySolver.accepts lits in
       TheorySolver.disequalities local_lits
       |> List.find_map (fun (l, r, original_lit) ->
            if List.mem (normalize_pair (l, r)) known_eqs then
              Some original_lit
            else
              None))

let explain_lit (assumptions : 'k assumption list) (lit : 'k literal)
  : 'k literal list =
  match List.find_opt (fun a -> a.lit = lit) assumptions with
  | Some a -> a.reason
  | None -> [lit]

let explain_core (assumptions : 'k assumption list) (core : 'k literal list)
  : 'k literal list =
  core
  |> List.concat_map (explain_lit assumptions)
  |> List.sort_uniq compare

let solve_each
  (theories : (module THEORY) list)
  (assumptions : 'k assumption list)
  : 'k theory_solution =
  let lits = literals_from_assumptions assumptions in
  let rec loop models = function
    | [] -> Theory_sat (List.fold_left Model.merge Model.empty models)
    | (_i, (module TheorySolver : THEORY)) :: rest ->
      let local_lits = List.filter TheorySolver.accepts lits in
      match TheorySolver.solve local_lits with
      | Theory_sat model -> loop (model :: models) rest
      | Theory_unsat core ->
        let explained = explain_core assumptions core
        in Theory_unsat explained
      | _ -> failwith "unreachable"
  in
  theories
  |> List.mapi (fun i theory -> i, theory)
  |> loop []

(** [combined theories] accepts a THEORIES list of domain-specific solvers
    and runs the Nelson Oppen merge algorithm against them to return 1 theory solver *)
let combine (theories : (module THEORY) list) : 'k theory_solver =
  fun (lits : 'k literal list) ->
    let assumptions, known_eqs =
      propagate_equalities theories (literals_to_assumptions lits) []
    in
    let propagated_lits = literals_from_assumptions assumptions in
    match solve_each theories assumptions with
    | Theory_sat model ->
      begin match find_disequality_conflict theories propagated_lits known_eqs with
      | Some original_lit -> Theory_unsat (explain_core assumptions [original_lit])
      | None -> Theory_sat model
      end
    | ts -> ts

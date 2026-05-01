open Utils

type 'k smt_atom =
  | Bool_key of (bool, 'k) Symbol.t
  | Predicate : ('a * 'a * bool) Binop.t * ('a, 'k) Formula.t * ('a, 'k) Formula.t -> 'k smt_atom

type 'k smt_literal =
  | Pos of 'k smt_atom
  | Neg of 'k smt_atom

type 'k t =
  { smt_to_sat : ('k smt_atom, Sat.Formula.atom) Hashtbl.t
  ; sat_to_smt : (Sat.Formula.atom, 'k smt_atom) Hashtbl.t
  }

let make () = { smt_to_sat = Hashtbl.create 64 ; sat_to_smt = Hashtbl.create 64 }

let abstract_atom (conn : 'k t) (atom : 'k smt_atom) : Sat.Formula.atom =
  match Hashtbl.find_opt conn.smt_to_sat atom with
  | Some uid -> uid
  | None ->
      let uid = Uid.make_new () in
      Hashtbl.add conn.smt_to_sat atom uid;
      Hashtbl.add conn.sat_to_smt uid atom;
      uid

let abstract_literal (conn : 'k t) (lit : 'k smt_literal) : Sat.Formula.literal =
  match lit with
  | Neg smt_atom -> Sat.Formula.Neg (abstract_atom conn smt_atom)
  | Pos smt_atom -> Sat.Formula.Pos (abstract_atom conn smt_atom)

let abstract_clause (conn : 'k t) (clause : 'k smt_literal list) : Sat.Formula.literal list =
  List.map (abstract_literal conn) clause

let abstract (conn : 'k t) (form : 'k smt_literal list list) : Sat.Formula.literal list list =
  List.map (abstract_clause conn) form

let from_smt_atom (atom : (bool, 'k) Formula.t) : 'k smt_atom =
  match atom with
  | Formula.Key key -> Bool_key key
  | Formula.Binop (op, left, right) -> Predicate (op, left, right)
  | Formula.Not _ | Formula.And _ | Formula.Const_bool _ ->
    failwith "That's not a Key or Binop"

let from_smt_literal (lit : (bool, 'k) Formula.t) : 'k smt_literal =
  match lit with
  | Formula.Not inner -> Neg (from_smt_atom inner)
  | inner -> Pos (from_smt_atom inner)

let from_smt_clause (clause : (bool, 'k) Formula.t list) : 'k smt_literal list =
  List.map from_smt_literal clause

let from_smt_formula (form : (bool, 'k) Formula.t) : 'k smt_literal list list =
  let clauses = Formula.clauses_from form in
  let explicit_clauses = List.map Formula.disjuncts_from_clause clauses in
  List.map from_smt_clause explicit_clauses

let mk_literal (conn : 'k t) (sat_model : Sat.Formula.literal list) (sat_atom : Sat.Formula.atom) : 'k smt_literal =
  match Hashtbl.find_opt conn.sat_to_smt sat_atom with
  | None -> failwith "unknown SAT atom"
  | Some smt_atom ->
    match Sat.Model.value_opt sat_atom sat_model with
    | None -> failwith "SAT atom unassigned"
    | Some Pos _ -> Pos smt_atom
    | Some Neg _ -> Neg smt_atom

let literals_from_model (conn : 'k t) (sat_model : Sat.Formula.literal list) =
  List.map
    (function
     | Sat.Formula.Pos sat_atom
     | Sat.Formula.Neg sat_atom -> mk_literal conn sat_model sat_atom)
    sat_model

let theory_learn (conn : 'k t) (core : 'k smt_literal list) : Sat.Formula.literal list =
  core
  |> List.map (abstract_literal conn)
  |> List.map Sat.Formula.negate

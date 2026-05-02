open Utils

type 'k t =
  { to_sat : ('k Theory.atom, Sat.Formula.atom) Hashtbl.t
  ; from_sat : (Sat.Formula.atom, 'k Theory.atom) Hashtbl.t
  }

let make () = { to_sat = Hashtbl.create 64 ; from_sat = Hashtbl.create 64 }

let abstract_atom (conn : 'k t) (atom : 'k Theory.atom) : Sat.Formula.atom =
  match Hashtbl.find_opt conn.to_sat atom with
  | Some uid -> uid
  | None ->
      let uid = Uid.make_new () in
      Hashtbl.add conn.to_sat atom uid;
      Hashtbl.add conn.from_sat uid atom;
      uid

let abstract_literal (conn : 'k t) (lit : 'k Theory.literal) : Sat.Formula.literal =
  match lit with
  | Neg smt_atom -> Sat.Formula.Neg (abstract_atom conn smt_atom)
  | Pos smt_atom -> Sat.Formula.Pos (abstract_atom conn smt_atom)

let abstract_clause (conn : 'k t) (clause : 'k Theory.literal list) : Sat.Formula.literal list =
  List.map (abstract_literal conn) clause

let abstract (conn : 'k t) (form : 'k Theory.literal list list) : Sat.Formula.literal list list =
  List.map (abstract_clause conn) form

let mk_literal (conn : 'k t) (sat_model : Sat.Formula.literal list) (sat_atom : Sat.Formula.atom) : 'k Theory.literal =
  match Hashtbl.find_opt conn.from_sat sat_atom with
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

let theory_learn (conn : 'k t) (core : 'k Theory.literal list) : Sat.Formula.literal list =
  core
  |> List.map (abstract_literal conn)
  |> List.map Sat.Formula.negate

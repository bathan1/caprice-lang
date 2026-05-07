open Utils

type 'k t =
  { to_sat : ('k Theory.atom, Sat.Formula.atom) Hashtbl.t
  ; from_sat : (Sat.Formula.atom, 'k Theory.atom) Hashtbl.t
  ; mutable count : int
  }

let make () =
  { to_sat = Hashtbl.create 64
  ; from_sat = Hashtbl.create 64
  ; count = 0
  }

let next_uid ?(uid = fun _count -> Uid.make_new ()) (conn : 'k t) : Uid.t =
  let fresh = uid conn.count in
  conn.count <- conn.count + 1;
  fresh

let abstract_atom
    ?uid
    (atom : 'k Theory.atom)
    (conn : 'k t)
  : Sat.Formula.atom =
  match Hashtbl.find_opt conn.to_sat atom with
  | Some uid -> uid
  | None ->
      let sat_atom = next_uid ?uid conn in
      Hashtbl.add conn.to_sat atom sat_atom;
      Hashtbl.add conn.from_sat sat_atom atom;
      sat_atom

let abstract_literal
    ?uid
    (lit : 'k Theory.literal)
    (conn : 'k t)
  : Sat.Formula.literal =
  match lit with
  | Neg smt_atom -> Sat.Formula.neg (abstract_atom ?uid smt_atom conn)
  | Pos smt_atom -> Sat.Formula.pos (abstract_atom ?uid smt_atom conn)

let abstract_clause
    ?uid
    (clause : 'k Theory.literal list)
    (conn : 'k t)
  : Sat.Formula.literal list =
  List.map (fun lit -> abstract_literal ?uid lit conn) clause

let abstract
    ?uid
    (formula : 'k Theory.literal list list)
    (conn : 'k t)
  : Sat.Formula.literal list list =
  List.map (fun clause -> abstract_clause ?uid clause conn) formula

let mk_literal (sat_model : Sat.Formula.literal list) (sat_atom : Sat.Formula.atom) (conn : 'k t) : 'k Theory.literal =
  let smt_atom = Hashtbl.find conn.from_sat sat_atom in
  match Sat.Model.find sat_atom sat_model with
  | Pos _ -> Pos smt_atom
  | Neg _ -> Neg smt_atom

let literals_from_model
  (sat_model : Sat.Formula.literal list)
  (conn : 'k t)
  : 'k Theory.literal list =
  List.map
    (function
     | Sat.Formula.Pos sat_atom
     | Sat.Formula.Neg sat_atom -> mk_literal sat_model sat_atom conn)
    sat_model

let theory_learn (core : 'k Theory.literal list) (conn : 'k t) : Sat.Formula.literal list =
  core
  |> List.map (fun lit -> abstract_literal lit conn)
  |> List.map Sat.Formula.negate

let cdcl_T ~(theory : 'k Theory.theory_solver) (formula : (bool, 'k) Formula.t)
  : 'k Solution.t =
  let conn = make () in
  let propositional = abstract (Theory.from_smt_formula formula) conn in
  let rec loop conn sat_formula =
    match Sat.Cdcl.cdcl sat_formula with
    | None -> Solution.Unsat
    | Some model ->
      let smt_lits =
        literals_from_model model conn
      in
      match theory smt_lits with
      | Theory_unsat core ->
        let learned = theory_learn core conn in
        let sat_formula' = Sat.Formula.conjoin1 learned sat_formula in
        loop conn sat_formula'
      | Theory_sat model -> Solution.Sat model
      | Theory_split clauses ->
        let sat_formula' =
          List.fold_left
            (fun acc clause ->
              let sat_clause = abstract_clause clause conn in
              Sat.Formula.conjoin1 sat_clause acc)
            sat_formula
            clauses
        in
        loop conn sat_formula'
  in
  loop conn propositional


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
  | Neg smt_atom -> Sat.Formula.Neg (abstract_atom ?uid smt_atom conn)
  | Pos smt_atom -> Sat.Formula.Pos (abstract_atom ?uid smt_atom conn)

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
  match Hashtbl.find_opt conn.from_sat sat_atom with
  | None -> failwith "unknown SAT atom"
  | Some smt_atom ->
    match Sat.Model.value_opt sat_atom sat_model with
    | None -> failwith "SAT atom unassigned"
    | Some Pos _ -> Pos smt_atom
    | Some Neg _ -> Neg smt_atom

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

let literal_from_sat
  (lit : Sat.Formula.literal)
  (conn : 'k t)
  : 'k Theory.literal =
  match lit with
  | Sat.Formula.Pos atom ->
      Theory.Pos (Hashtbl.find conn.from_sat atom)

  | Sat.Formula.Neg atom ->
      Theory.Neg (Hashtbl.find conn.from_sat atom)

let clause_from_sat
  (clause : Sat.Formula.literal list)
  (conn : 'k t)
  : 'k Theory.literal list =
  List.map (fun lit -> literal_from_sat lit conn) clause

let from_sat_formula
  (sat_formula : Sat.Formula.t)
  (conn : 'k t)
  : 'k Theory.literal list list =
  List.map (fun clause -> clause_from_sat clause conn) sat_formula

(* let literals_for_theory *)
(*   ~(theory : (module Theory.THEORY)) *)
(*   (model : Sat.Formula.literal list) *)
(*   (conn : 'k t) *)
(*   : 'k Theory.literal list = *)
(*   List.filter () *)

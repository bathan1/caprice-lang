let contains_unsolvable formula =
  Formula.contains_binops [Times ; Divide ; Modulus ; Plus] formula

let cdcl_T ~(solver : 'k Theory.theory_solver) (formula : (bool, 'k) Formula.t)
  : 'k Solution.t =
  let conn = Connector.make 64 in
  let propositional = Connector.abstract (Theory.from_smt_formula formula) conn in
  let rec loop conn sat_formula =
    match Sat.Cdcl.cdcl sat_formula with
    | UNSAT -> Solution.Unsat
    | SAT model ->
      let theory_lits =
        Connector.make_theory_literals model conn
      in
      match solver theory_lits with
      | Theory_unknown -> Solution.Unknown
      | Theory_unsat core ->
        let learned = Connector.theory_learn core conn in
        let sat_formula' = Sat.Formula.conjoin1 learned sat_formula in
        loop conn sat_formula'
      | Theory_sat model -> Solution.Sat model
      | Theory_split clauses ->
        let sat_formula' =
          List.fold_left
            (fun acc clause ->
              let sat_clause = Connector.abstract_clause clause conn in
              Sat.Formula.conjoin1 sat_clause acc)
            sat_formula
            clauses
        in
        loop conn sat_formula'
  in
  loop conn propositional

type 'k solver = (bool, 'k) Formula.t -> 'k Solution.t

let blue3
  : type k. solver:k Theory.theory_solver -> k solver -> (bool, k) Formula.t -> k Solution.t =
  fun ~solver next formula ->
  let solve formula = cdcl_T ~solver formula in
  if contains_unsolvable formula then next formula
  else
    match formula with
    | Const_bool true -> Solution.Sat Model.empty
    | Const_bool false -> Solution.Unsat
    | _ ->
      match solve formula with
      | Solution.Unknown -> next formula
      | solution -> solution

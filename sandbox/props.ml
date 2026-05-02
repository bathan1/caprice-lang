[@@@ocaml.warning "-26"]
[@@@ocaml.warning "-27"]
[@@@ocaml.warning "-32"]

open Sat
open Sat.Formula

let pos x = Pos (Utils.Uid.of_int x)
let neg x = Neg (Utils.Uid.of_int x)

let form : Formula.t = [
  [ neg 1 ; neg 2 ];
  [ neg 1 ; pos 3 ];
  [ neg 3 ; neg 4 ];
  [ pos 2 ; pos 4 ; pos 5 ];
  [ neg 5 ; pos 6 ; neg 7 ];
  [ pos 2 ; pos 7 ; pos 8 ];
  [ neg 8 ; neg 9 ];
  [ neg 8 ; pos 10 ];
  [ pos 9 ; neg 10 ; pos 11 ];
  [ neg 10 ; neg 12 ];
  [ neg 11 ; pos 12 ]
]

let trail : Trail.t list = [
  { lit = pos 1 ; level = 1 ; reason = Decided };
  { lit = neg 2
  ; level = 1
  ; reason = Propagated [neg 1 ; neg 2]
  };
  { lit = pos 3 
  ; level = 1
  ; reason = Propagated [neg 1 ; pos 3]
  };
  { lit = neg 4
  ; level = 1
  ; reason = Propagated [neg 3 ; neg 4]
  };
  { lit = pos 5
  ; level = 1
  ; reason = Propagated [pos 2 ; pos 4 ; pos 5]
  };
  { lit = neg 6
  ; level = 2
  ; reason = Decided
  };
  { lit = neg 7
  ; level = 2
  ; reason = Propagated [neg 5; pos 6; neg 7]
  };
  { lit = pos 8
  ; level = 2
  ; reason = Propagated [pos 2; pos 7; pos 8]
  };
  { lit = neg 9
  ; level = 2
  ; reason = Propagated [neg 8; neg 9]
  };
  { lit = pos 10
  ; level = 2
  ; reason = Propagated [neg 8; pos 10]
  };
  { lit = pos 11
  ; level = 2
  ; reason = Propagated [pos 9; neg 10 ; pos 11]
  };
  { lit = neg 12
  ; level = 2
  ; reason = Propagated [neg 10; neg 12]
  };
]

let conflict = [ neg 11 ; pos 12 ]

open Smt
(*
  Original constraints:

    (x1 <= x3 - 6) ∧ (x1 <= x4 - 3) ∧
    (x2 <= x1 + 3) ∧ (x3 <= x2 + 2) ∧
    (x3 <= x4 - 1) ∧ (x4 <= x2 + 5)

  ASCII variable mapping:

    x1 -> a
    x2 -> b
    x3 -> c
    x4 -> d

  Rewritten:

    (a <= c - 6) ∧ (a <= d - 3) ∧
    (b <= a + 3) ∧ (c <= b + 2) ∧
    (c <= d - 1) ∧ (d <= b + 5)

  Difference-logic form:

    a - c <= -6
    a - d <= -3
    b - a <=  3
    c - b <=  2
    c - d <= -1
    d - b <=  5
*)
let unsat_form =
  let module AsciiSymbol = Symbol.AsciiSymbol in
  let a = AsciiSymbol.make_int 'a' in
  let b = AsciiSymbol.make_int 'b' in
  let c = AsciiSymbol.make_int 'c' in
  let d = AsciiSymbol.make_int 'd' in
  [
    Formula.binop
      Binop.Less_than_eq
      (Formula.symbol a)
      (Formula.binop Binop.Minus (Formula.symbol c) (Formula.const_int 6));

    Formula.binop
      Binop.Less_than_eq
      (Formula.symbol a)
      (Formula.binop Binop.Minus (Formula.symbol d) (Formula.const_int 3));

    Formula.binop
      Binop.Less_than_eq
      (Formula.symbol b)
      (Formula.binop Binop.Plus (Formula.symbol a) (Formula.const_int 3));

    Formula.binop
      Binop.Less_than_eq
      (Formula.symbol c)
      (Formula.binop Binop.Plus (Formula.symbol b) (Formula.const_int 2));

    Formula.binop
      Binop.Less_than_eq
      (Formula.symbol c)
      (Formula.binop Binop.Minus (Formula.symbol d) (Formula.const_int 1));

    Formula.binop
      Binop.Less_than_eq
      (Formula.symbol d)
      (Formula.binop Binop.Plus (Formula.symbol b) (Formula.const_int 5));
  ]

let pp_list pp_item fmt xs =
  Format.fprintf fmt "[@[<hov>";
  List.iteri
    (fun i x ->
      if i > 0 then Format.fprintf fmt ";@ ";
      pp_item fmt x)
    xs;
  Format.fprintf fmt "@]]"

let model_key_to_string : type k. k Model.key -> string = function
  | Model.Bool_key sym -> Symbol.AsciiSymbol.to_string (Symbol.to_uid sym)
  | Model.Int_key sym -> Symbol.AsciiSymbol.to_string (Symbol.to_uid sym)

let () =
  let as_t_lits = List.flatten (Theory.from_smt_formula unsat_form) in
  let res = Idl.idl as_t_lits in

  Format.printf
    "%a@."
    (Solution.pp_theory_solution
       ~key:model_key_to_string
       (pp_list Theory.pp_literal))
    res

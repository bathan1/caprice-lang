[@@@ocaml.warning "-26"]
[@@@ocaml.warning "-27"]
[@@@ocaml.warning "-32"]

open Sat
open Sat.Formula

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
  { lit = pos 1 ; level = 1 ; reason = Decision };
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
  ; reason = Decision
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

let () =
  let clause, lvl = Cdcl.analyze_conflict conflict trail 2 in
  (Formula.pp_clause stdout clause);
  Printf.printf "lvl=%d\n" lvl;

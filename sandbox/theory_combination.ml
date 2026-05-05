open Smt

let input = "(a <= 100) ^ (a = b) ^ (b = c) ^ (not (c = 100))"

let theory_combination () =
  let formula = Boolean.parse input in
  let conn = Connector.make () in

  let smt_formula = Theory.from_smt_formula @@ Formula.clauses_from formula in
  let sat_formula = Connector.abstract ~uid:(fun count -> Utils.Uid.of_int (Char.code 'p' + count)) smt_formula conn in
  let () =
    Printf.printf "\nSMT Formula: ";
    Printer.print_formula smt_formula ~key:Model.ascii_key;

    Printf.printf "SAT Formula: ";
    Sat.Formula.print_formula sat_formula ~uid:Symbol.AsciiSymbol.to_string;
    print_newline ()
  in

  let euf_solvable = List.filter Euf.accepts (List.flatten smt_formula) in
  let idl_solvable = List.filter Idl.accepts (List.flatten smt_formula) in

  let () = 
    Printf.printf "EUF accepts:\n";
    Printer.print_delim_literals euf_solvable ~key:Model.ascii_key;
    print_newline ()
  in
  let () =
    Printf.printf "IDL accepts:\n";
    Printer.print_delim_literals idl_solvable ~key:Model.ascii_key;
    print_newline ()
  in

  let () =
    let shared_vars =
      Theory.find_shared_variables ~accepts:[Euf.accepts ; Idl.accepts] smt_formula
    in
    Printf.printf "Shared variables are: ";
    List.iter (Printer.print_shared ~uid:Symbol.AsciiSymbol.to_string) shared_vars
  in

  ()

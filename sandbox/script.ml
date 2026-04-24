[@@@ocaml.warning "-26"]
[@@@ocaml.warning "-27"]
[@@@ocaml.warning "-32"]

open Smt
open Utils

module AsciiSymbol = Symbol.Make (struct
  type t = char

  let uid t = t |> Char.code |> Utils.Uid.of_int
end)

let make_bool = AsciiSymbol.make_bool
let make_int = fun x -> x |> AsciiSymbol.make_int |> Formula.symbol
let a = make_bool 'a'
let b = make_bool 'b'
let c = make_bool 'c'
let d = make_bool 'd'
let or_ l r = Formula.binop Binop.Or l r

let clauses =
  [
    or_ (Formula.symbol a) (Formula.symbol b);
    or_ (Formula.symbol c) (Formula.symbol d);
    Formula.not_ (Formula.symbol b);
  ]

let uid_to_string = fun uid -> uid |> Uid.to_int |> Char.chr |> String.of_char

let uid_to_symbol_string =
 fun uid ->
  ( AsciiSymbol.make_int (uid |> Uid.to_int |> Char.chr),
    uid |> Uid.to_int |> Char.chr |> String.of_char )

let to_string = Formula.to_string ~uid:uid_to_string
let a = Formula.symbol (AsciiSymbol.make_int 'a')
let b = Formula.symbol (AsciiSymbol.make_int 'b')

let solution_text (solution : 'k Solution.t) : string =
  Solution.to_string solution ~uid:(fun uid ->
      ( AsciiSymbol.make_int (uid |> Uid.to_int |> Char.chr),
        uid |> Uid.to_int |> Char.chr |> String.of_char ))

open Printf
open Overlays

let main_solve = Solve.main_solve (module Typed_z3.Default)

let sanity_check () =
  let fs = [ "(a <= 0) ^ (0 <= (b + a)) ^ (b < 0)" ] in
  let iter =
   fun i f_text ->
    let f = Boolean.parse f_text in
    let res = main_solve f in
    match res with
    | Solution.Unknown -> failwith "never should happen"
    | Solution.Unsat -> (
        let z3_result = Solve.direct_solve (module Typed_z3.Default) f in
        match z3_result with
        | Unsat -> true
        | Unknown -> failwith "never should happen"
        | Sat _ -> false)
    | Solution.Sat model ->
        f |> Formula.symbols |> Uid.Set.to_list
        |> List.fold_left
             (fun acc uid ->
               let binding = model.value (I uid) in
               match binding with None -> acc && false | Some _ -> acc && true)
             true
        |> fun is_full_assigment ->
        if not is_full_assigment then false
        else
          let eval_result = Formula.default_eval model f in
          let () =
            if not eval_result then
              printf "(%d : %s) Inconsistent model:\n%s\n" (i + 1) f_text
                (Model.to_string model ~uid:uid_to_symbol_string)
          in
          eval_result
  in
  let results = List.mapi iter fs in
  let bad_results =
    List.filter_mapi
      (fun i res -> if not res then Some (i + 1) else None)
      results
  in
  if List.is_empty bad_results then Printf.printf "checks out!\n"
  else Printf.printf "Invalid formulas:";
  List.iter (fun res -> printf "%d, " res) bad_results

open Unix

let sql_escape (s : string) =
  s |> String.split_on_char '\'' |> String.concat "''"

let time_us_float f =
  let t1 = gettimeofday () in
  let _ = f () in
  let t2 = gettimeofday () in
  (t2 -. t1) *. 1_000_000.0

let benchmark num_trials =
  let solve_z3_only = Solve.direct_solve (module Typed_z3.Default) in
  let fs = Boolean.from_stdin () in

  Printf.printf
    "CREATE TABLE IF NOT EXISTS benchmark_results (\n\
    \  trial_num INTEGER NOT NULL,\n\
    \  formula_id INTEGER NOT NULL,\n\
    \  formula TEXT NOT NULL,\n\
    \  time_us_blue3 FLOAT NOT NULL,\n\
    \  time_us_z3 FLOAT NOT NULL\n\
     );\n\n";

  let rec aux trial_num =
    if trial_num = num_trials then ()
    else begin
      fs
      |> List.iteri (fun formula_id ftext ->
          let formula_sql = sql_escape ftext in

          let time_us_blue3 =
            time_us_float (fun () ->
                let f = Boolean.parse ftext in
                ignore (main_solve f))
          in

          let time_us_z3 =
            time_us_float (fun () ->
                let f = Boolean.parse ftext in
                ignore (solve_z3_only f))
          in

          Printf.printf
            "INSERT INTO benchmark_results (trial_num, formula_id, formula, \
             time_us_blue3, time_us_z3) VALUES (%d, %d, '%s', %.6f, %.6f);\n"
            trial_num formula_id formula_sql time_us_blue3 time_us_z3);

      aux (trial_num + 1)
    end
  in
  aux 0

let () = benchmark 5

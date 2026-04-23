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

let make_int = fun x ->
  x
  |> AsciiSymbol.make_int
  |> Formula.symbol

let a = (make_bool 'a') 
let b = make_bool 'b' 
let c = make_bool 'c'
let d = make_bool 'd'

let or_ l r = Formula.binop Binop.Or l r

let clauses = [
  or_ (Formula.symbol a) (Formula.symbol b);
  or_ (Formula.symbol c) (Formula.symbol d);
  Formula.not_ (Formula.symbol b)
]

let uid_to_string = (fun uid ->
  uid |> Uid.to_int |> Char.chr |> String.of_char
)

let to_string = Formula.to_string ~uid:uid_to_string
let a = Formula.symbol (AsciiSymbol.make_int 'a')
let b = Formula.symbol (AsciiSymbol.make_int 'b')

let solution_text (solution : 'k Solution.t) : string = 
  Solution.to_string solution ~uid:(fun uid ->
    AsciiSymbol.make_int (uid |> Uid.to_int |> Char.chr),
    uid |> Uid.to_int |> Char.chr |> String.of_char
  )

open Printf
open Overlays

let main_solve = Solve.main_solve (module Typed_z3.Default)

let () =
  let fs = Boolean.from_stdin () in
  let iter = fun i f_text -> 
    let f = Boolean.parse f_text in
    let res = main_solve f in
    match res with
    | Solution.Unknown -> failwith "never should happen"
    | Solution.Unsat -> (
      let z3_result = Solve.direct_solve (module Typed_z3.Default) f in
      match z3_result with
      | Unsat -> true
      | Unknown -> failwith "never should happen"
      | Sat _ -> false
    )
    | Solution.Sat model -> (
      f
      |> Formula.symbols
      |> Uid.Set.to_list
      |> List.fold_left (fun acc uid ->
        let binding = model.value (I uid) in
        match binding with
        | None -> acc && false
        | Some _ -> acc && true
      ) true
    )
  in
  let results = List.mapi iter fs in
  let bad_results = List.filter_mapi (fun i res -> 
    if not res then
      Some (i + 1)
    else
      None
  ) results in
  if List.is_empty bad_results then
    Printf.printf "checks out!\n"
  else
    Printf.printf "Invalid formulas:";
    List.iter (fun res -> printf "%d, " res) bad_results;

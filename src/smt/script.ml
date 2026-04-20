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
let idl_clauses = Formula.and_ [
  Integer.greater_than_eq 
    (make_int 'x')
    (Formula.const_int 2);
]
;;

let solution_text (solution : 'k Solution.t) : string = 
  Solution.to_string solution ~uid:(fun uid ->
    AsciiSymbol.make_int (uid |> Uid.to_int |> Char.chr),
    uid |> Uid.to_int |> Char.chr |> String.of_char
  )

open Printf

let () =
  let sol = Integer.solve_int_diff idl_clauses 
  in
  let text = solution_text sol 
  in printf "IDL SOLUTION: %s\n" text;

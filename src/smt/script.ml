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

let ftext = "(48 <= a) ^ (57 < a) ^ (not (a = 108)) ^ (not (a = 105)) ^ (not (a = 98)) ^ (not (a = 97)) ^ (not (a = 61)) ^ (not (a = 45)) ^ (not (a = 43)) ^ (not (a = 42)) ^ (not (a = 41)) ^ (not (a = 40)) ^ (not (a = 32)) ^ (65 <= a)"

let solution_text (solution : 'k Solution.t) : string = 
  Solution.to_string solution ~uid:(fun uid ->
    AsciiSymbol.make_int (uid |> Uid.to_int |> Char.chr),
    uid |> Uid.to_int |> Char.chr |> String.of_char
  )

open Printf

let () =
  let f = (Boolean.parse ftext) in
  f
  |> Integer.rewrite
  |> fun rewritten -> 
  Printf.printf "rewritten %s\n" (Formula.to_string rewritten);
  rewritten
  |> Integer.to_propositional ~to_symbol:(
    fun uid ->
      uid
      |> fun c -> c + (Char.code 'p')
      |> Char.chr
      |> AsciiSymbol.make_bool
  )
  |> fun (prop, map) -> (
  let clauses = match prop with | And ls -> ls | f -> [f] in
    clauses
    |> Boolean.dpll ~decode:(fun uid -> Uid.Map.find uid map) ~solve:Integer.solve
    |> fun s -> printf "%s\n" (solution_text s)
  )

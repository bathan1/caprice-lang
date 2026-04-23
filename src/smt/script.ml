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

let main_solve = Boolean.dpll
  ~to_symbol:(fun uid -> 
    uid
    |> fun c -> c + (Char.code 'p')
    |> Char.chr
    |> AsciiSymbol.make_bool
  )
  ~solvers:[Integer.solve_int_diff]
  (fun _ -> raise (Invalid_argument "lol"))

let () =
  let fs = Boolean.from_stdin () in
  let iter = fun f -> 
    let () = Printf.printf "Solution %s: " f in
    let res = main_solve (Boolean.parse f) in
    printf "%s\n" (solution_text res);
  in
  List.iter iter fs;

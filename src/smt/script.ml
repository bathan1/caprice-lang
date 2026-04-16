open Smt
open Smt.Formula

module AsciiSymbol = Symbol.Make (struct
  type t = char
  let uid t = t |> Char.code |> Utils.Uid.of_int
end)

let make_int x = 
  function
  | x -> x |> AsciiSymbol.make_int |> symbol
let make_bool = 
  function
  | x -> x |> AsciiSymbol.make_bool |> symbol

let p = make_bool 'p'
let q = make_bool 'q'
let r = make_bool 'r'

let ast = not_ (
  and_ [
    p;
    binop Or q (not_ r)
  ]
)

let size = count ast

let () = Printf.printf "size is %d\n" size

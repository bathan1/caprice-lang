[@@@ocaml.warning "-26"]
[@@@ocaml.warning "-27"]
[@@@ocaml.warning "-32"]

open Smt
open Utils

module AsciiSymbol = Symbol.Make (struct
  type t = char
  let uid t = t |> Char.code |> Utils.Uid.of_int
end)

let make_bool = 
  function
  | x -> x |> AsciiSymbol.make_bool

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

let to_string = Formula.to_string ~uid:(fun uid ->
  uid |> Uid.to_int |> Char.chr |> String.of_char
)

let () = 
  (* let simplified, model = Boolean.unit_propagate clauses in *)
  (* Printf.printf "%s\n" (to_string (Formula.and_ simplified)); *)
  (* [ *)
  (*   a; *)
  (*   b; *)
  (*   c; *)
  (*   d; *)
  (* ] *)
  (* |> List.iter (fun s ->  *)
  (*   Printf.printf "%c = %s\n" *)
  (*   ( *)
  (*     s *)
  (*     |> function  *)
  (*       | Symbol.B uid -> *)
  (*         uid |> Uid.to_int |> Char.chr *)
  (*   ) *)
  (*   (s |> model.value |> *)
  (*     function *)
  (*     | None -> "NOT_ASSIGNED" *)
  (*     | Some truth_value -> if truth_value then "true" else "false") *)
  (* ) *)
  let res = Boolean.dpll clauses in
  Printf.printf "%s\n" (
    Solution.to_string res ~uid:(fun uid ->
      AsciiSymbol.make_bool (Char.chr (Uid.to_int uid)),
      uid |> Uid.to_int |> Char.chr |> String.of_char
    )
  )

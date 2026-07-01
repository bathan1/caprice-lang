open Smt

module Web : Solve.SOLVABLE = struct
  type ('a, 'k) t =
    | Int of int
    | Bool of bool
    | Symbol : ('a, 'k) Symbol.t -> ('a, 'k) t
    | Unknown_expr

  let equal a b = a = b

  let const_int i = Int i
  let const_bool b = Bool b

  let symbol s = Symbol s

  let not_ = function
    | Bool b -> Bool (not b)
    | _ -> Unknown_expr

  let binop : type a b c.
    (a * a * b, c) Binop.c ->
    (a, 'k) t ->
    (a, 'k) t ->
    (b, 'k) t =
    fun op x y ->
      match op, x, y with
      | Plus, Int a, Int b -> Int (a + b)
      | Minus, Int a, Int b -> Int (a - b)
      | Times, Int a, Int b -> Int (a * b)
      | Divide, Int a, Int b -> Int (a / b)
      | Modulus, Int a, Int b -> Int (a mod b)

      | Less_than, Int a, Int b -> Bool (a < b)
      | Less_than_eq, Int a, Int b -> Bool (a <= b)
      | Greater_than, Int a, Int b -> Bool (a > b)
      | Greater_than_eq, Int a, Int b -> Bool (a >= b)

      | Equal, a, b -> Bool (equal a b)
      | Iff, Bool a, Bool b -> Bool (a = b)
      | Not_equal, a, b -> Bool (not (equal a b))

      | Or, Bool a, Bool b -> Bool (a || b)

      | _ -> Unknown_expr

  let is_const = function
    | Int _
    | Bool _ -> true
    | Symbol _
    | Unknown_expr -> false

  let and_ exprs =
    if List.exists ((=) (Bool false)) exprs then Bool false
    else if List.for_all ((=) (Bool true)) exprs then Bool true
    else Unknown_expr

  let or_ exprs =
    if List.exists ((=) (Bool true)) exprs then Bool true
    else if List.for_all ((=) (Bool false)) exprs then Bool false
    else Unknown_expr

  let solve = function
    | Bool false -> Solution.Unsat
    | _ -> Solution.Unknown
end

include Web
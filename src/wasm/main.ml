open Js_of_ocaml

let solve = Smt.Solve.main_solve (module Dummy_solver)

exception Parse_error of string

type token =
  | Int of int | Ident of string
  | Lparen | Rparen | Plus | Minus
  | And | Or | Not
  | Eq | Neq | Lt | Le | Gt | Ge
  | End

let tokenize input =
  let length = String.length input in
  let is_digit c = c >= '0' && c <= '9' in
  let is_ident_start c =
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c = '_'
  in
  let is_ident_char c = is_ident_start c || is_digit c in
  let rec skip_comment i =
    if i < length && input.[i] <> '\n' then skip_comment (i + 1) else i
  in
  let rec number i =
    if i < length && is_digit input.[i] then number (i + 1) else i
  in
  let rec identifier i =
    if i < length && is_ident_char input.[i] then identifier (i + 1) else i
  in
  let rec loop i tokens =
    if i >= length then Array.of_list (List.rev (End :: tokens))
    else
      match input.[i] with
      | ' ' | '\t' | '\r' | '\n' -> loop (i + 1) tokens
      | '#' -> loop (skip_comment (i + 1)) tokens
      | '(' -> loop (i + 1) (Lparen :: tokens)
      | ')' -> loop (i + 1) (Rparen :: tokens)
      | '+' -> loop (i + 1) (Plus :: tokens)
      | '-' -> loop (i + 1) (Minus :: tokens)
      | '^' -> loop (i + 1) (And :: tokens)
      | '&' when i + 1 < length && input.[i + 1] = '&' ->
        loop (i + 2) (And :: tokens)
      | '|' ->
        let next = if i + 1 < length && input.[i + 1] = '|' then i + 2 else i + 1 in
        loop next (Or :: tokens)
      | '!' when i + 1 < length && input.[i + 1] = '=' ->
        loop (i + 2) (Neq :: tokens)
      | '!' -> loop (i + 1) (Not :: tokens)
      | '=' when i + 1 < length && input.[i + 1] = '=' ->
        loop (i + 2) (Eq :: tokens)
      | '=' -> loop (i + 1) (Eq :: tokens)
      | '<' when i + 1 < length && input.[i + 1] = '=' ->
        loop (i + 2) (Le :: tokens)
      | '<' -> loop (i + 1) (Lt :: tokens)
      | '>' when i + 1 < length && input.[i + 1] = '=' ->
        loop (i + 2) (Ge :: tokens)
      | '>' -> loop (i + 1) (Gt :: tokens)
      | c when is_digit c ->
        let stop = number (i + 1) in
        let value = String.sub input i (stop - i) |> int_of_string in
        loop stop (Int value :: tokens)
      | c when is_ident_start c ->
        let stop = identifier (i + 1) in
        let identifier = String.sub input i (stop - i) in
        let token = if identifier = "not" then Not else Ident identifier in
        loop stop (token :: tokens)
      | c ->
        raise (Parse_error (Printf.sprintf "unexpected character %C at offset %d" c i))
  in
  loop 0 []

type parser =
  { tokens : token array
  ; mutable position : int
  ; names : (string, Utils.Uid.t) Hashtbl.t
  ; reverse_names : (int, string) Hashtbl.t
  }

let current parser = parser.tokens.(parser.position)

let advance parser =
  let token = current parser in
  parser.position <- parser.position + 1;
  token

let expect parser expected description =
  if current parser = expected then ignore (advance parser)
  else raise (Parse_error ("expected " ^ description))

let symbol parser name =
  let uid =
    match Hashtbl.find_opt parser.names name with
    | Some uid -> uid
    | None ->
      let uid = Utils.Uid.of_int (Hashtbl.length parser.names) in
      Hashtbl.add parser.names name uid;
      Hashtbl.add parser.reverse_names (Utils.Uid.to_int uid) name;
      uid
  in
  Smt.Formula.symbol (Smt.Symbol.I uid)

let rec parse_formula parser = parse_or parser

and parse_or parser =
  let first = parse_and parser in
  let rec loop expressions =
    match current parser with
    | Or ->
      ignore (advance parser);
      loop (parse_and parser :: expressions)
    | _ -> Smt.Formula.or_ (List.rev expressions)
  in
  loop [first]

and parse_and parser =
  let first = parse_not parser in
  let rec loop expressions =
    match current parser with
    | And ->
      ignore (advance parser);
      loop (parse_not parser :: expressions)
    | _ -> Smt.Formula.and_ (List.rev expressions)
  in
  loop [first]

and parse_not parser =
  match current parser with
  | Not ->
    ignore (advance parser);
    Smt.Formula.not_ (parse_not parser)
  | _ -> parse_bool_atom parser

and parse_bool_atom parser =
  let saved_position = parser.position in
  let starts_with_lparen = current parser = Lparen in
  try parse_comparison parser with
  | Parse_error _ as error when not starts_with_lparen -> raise error
  | Parse_error _ ->
    parser.position <- saved_position;
    expect parser Lparen "'('";
    let formula = parse_formula parser in
    expect parser Rparen "')'";
    formula

and parse_comparison parser =
  let left = parse_add parser in
  let operator = advance parser in
  let right = parse_add parser in
  match operator with
  | Eq -> Smt.Formula.binop Smt.Binop.Equal left right
  | Neq -> Smt.Formula.binop Smt.Binop.Not_equal left right
  | Lt -> Smt.Formula.binop Smt.Binop.Less_than left right
  | Le -> Smt.Formula.binop Smt.Binop.Less_than_eq left right
  | Gt -> Smt.Formula.binop Smt.Binop.Greater_than left right
  | Ge -> Smt.Formula.binop Smt.Binop.Greater_than_eq left right
  | _ -> raise (Parse_error "expected a comparison operator (=, !=, <, <=, >, or >=)")

and parse_add parser =
  let first = parse_unary parser in
  let rec loop expression =
    match current parser with
    | Plus ->
      ignore (advance parser);
      loop (Smt.Formula.plus expression (parse_unary parser))
    | Minus ->
      ignore (advance parser);
      loop (Smt.Formula.minus expression (parse_unary parser))
    | _ -> expression
  in
  loop first

and parse_unary parser =
  match current parser with
  | Minus ->
    ignore (advance parser);
    Smt.Formula.minus (Smt.Formula.const_int 0) (parse_unary parser)
  | _ -> parse_arithmetic_atom parser

and parse_arithmetic_atom parser =
  match advance parser with
  | Int value -> Smt.Formula.const_int value
  | Ident name -> symbol parser name
  | Lparen ->
    let expression = parse_add parser in
    expect parser Rparen "')'";
    expression
  | _ ->
    raise (Parse_error "expected an integer, variable, or parenthesized arithmetic expression")

let solve_input input =
  if String.trim input = "" then raise (Parse_error "input is empty");
  let parser =
    { tokens = tokenize input
    ; position = 0
    ; names = Hashtbl.create 8
    ; reverse_names = Hashtbl.create 8
    }
  in
  let formula = parse_formula parser in
  expect parser End "end of input";
  let key model_key =
    let uid = Smt.Model.uid_from_key model_key |> Utils.Uid.to_int in
    Option.value
      (Hashtbl.find_opt parser.reverse_names uid)
      ~default:("v" ^ string_of_int uid)
  in
  Smt.Solution.to_string ~key (solve formula)

let smoke_test () =
  let open Smt in
  let x = Symbol.I (Utils.Uid.of_int 0) in
  let y = Symbol.I (Utils.Uid.of_int 1) in
  let formula =
    Formula.and_
      [ Formula.binop Binop.Less_than (Formula.symbol x) (Formula.symbol y)
      ; Formula.binop Binop.Less_than_eq (Formula.symbol y) (Formula.symbol x)
      ]
  in
  Solution.to_string ~key:(fun _ -> "unused") (solve formula)

let () =
  Js.export
    "capriceWasm"
    (object%js
       method solveSmokeTest = Js.string (smoke_test ())
       method solveInput input =
         let result =
           try solve_input (Js.to_string input) with
           | Parse_error message -> "Error: " ^ message
           | exn -> "Error: " ^ Printexc.to_string exn
         in
         Js.string result
     end)

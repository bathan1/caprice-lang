open Utils
exception Should_not_happen of string

module UidMap = Map.Make (Uid)

module AsciiSymbol = Symbol.Make (struct
  type t = char
  let uid t = t |> Char.code |> Utils.Uid.of_int
end)

let get_domain map =
  map
  |> UidMap.to_list
  |> List.map (fun (uid, _) -> uid)

let uid_to_string uid =
  uid |> Uid.to_int |> Char.chr |> String.make 1

let model_to_string uid_map_to_string =
  uid_map_to_string
  |> UidMap.bindings
  |> List.map (fun (uid, v) ->
       Printf.sprintf "%s=%b" (uid_to_string uid) v
     )
  |> String.concat ", "
  |> fun s -> "{ " ^ s ^ " }"

let clauses_to_string clauses =
  clauses
  |> List.map (Formula.to_string ~uid:uid_to_string)
  |> String.concat " ∧ "


let find_first_unit_literal (ls : (bool, 'k) Formula.t list) : ((bool, 'k) Symbol.t * bool) option =
  let open Formula in
  ls
  |> List.find_opt (
    function
    | Key _
      | Not (Key _) -> true
    | _ -> false
  )
  |> function
  | None -> None
  | Some v -> Some (
    match v with
    | Key key -> key, true
    | Not (Key key) -> key, false
    | _ ->
      raise (Should_not_happen "lol")
  )

let unit_propagate 
  (clauses : (bool, 'k) Formula.t list) 
  : (bool, 'k) Formula.t list * bool UidMap.t =
  let rec propagate clauses truth_tbl =
    match find_first_unit_literal clauses with
    | None -> clauses, truth_tbl
    | Some (key, value) ->
      let clauses_anded = Formula.and_ clauses in
      let uid = Symbol.to_uid key in
      let next_truthtbl = (UidMap.add uid value truth_tbl) in
      let next = Formula.subst value key clauses_anded in
      match next with
      | And next_ls -> 
        propagate next_ls next_truthtbl
      | rest ->
        [rest], next_truthtbl
  in 
  propagate clauses UidMap.empty

let rec choose_literal : type k. (bool, k) Formula.t list -> (bool, k) Symbol.t =
  function
  | [] -> 
    raise (Should_not_happen "lol")
  | hd :: tl ->
    match hd with
    | Formula.Binop (Binop.Or, Formula.Key key, _) -> key
    | Formula.Binop (Binop.Or, _, Formula.Key key ) -> key
    | _ -> choose_literal tl

let formula_to_clauses =
  function
  | Formula.And ls -> ls
  | e -> [e]
;;

let is_falsified_clause (model_state : bool UidMap.t) (vars : (Uid.Set.t)) : bool =
  vars
  |> Uid.Set.for_all (
    fun symbol -> 
    match UidMap.find_opt symbol model_state with
    | None -> false
    | Some v -> not v
  )

let dpll (clauses : (bool, 'k) Formula.t list) : 'k Solution.t =
  let rec dpll clauses model_state =
    if
      clauses 
      |> List.map Formula.symbols 
      |> List.exists (is_falsified_clause model_state)
    then Solution.Unsat
    else
      let clauses_subbed = (
        clauses
        |> Formula.and_
        |> Formula.subst 
      ) in
      let reduced, model = (
        clauses
        |> unit_propagate
        |> fun (e, partial) -> 
          e, 
          model_state 
          |> UidMap.union (fun _ _ new_v -> Some new_v) partial
      ) in
      match reduced with
      | clauses when 
        List.is_empty clauses ||
        clauses 
        |> List.for_all (
          function 
          | Formula.Const_bool true -> true 
          | _ -> false
        ) -> 
        let solution_model =
          model
          |> get_domain
          |> fun domain -> Model.of_local 
            domain 
            ~lookup:(fun uid -> UidMap.find_opt uid model)
        in
        Solution.Sat solution_model
      | ls when List.exists (function Formula.Const_bool false -> true | _ -> false) ls -> Solution.Unsat
      | next ->
        let branch_key = choose_literal next in
        let uid = Symbol.to_uid branch_key in 
        let left_model = (UidMap.add uid true model) in
        Printf.printf "\nbranch_key=%s, left_model=%s" (uid_to_string uid) (model_to_string left_model);
        match dpll next left_model with
        | Solution.Sat left_model -> 
          Solution.Sat left_model
        | Solution.Unsat ->
          let right_model = (UidMap.add uid false model) in
          Printf.printf ", right_model=%s" (model_to_string right_model);
          dpll next right_model
        | Solution.Unknown -> raise (Should_not_happen "unknown solution")
  in
  dpll clauses UidMap.empty
;;

open Utils
exception Should_not_happen of string

module AsciiSymbol = Symbol.Make (struct
  type t = char
  let uid t = t |> Char.code |> Utils.Uid.of_int
end)

let get_domain map =
  map
  |> Uid.Map.to_list
  |> List.map (fun (uid, _) -> uid)

let uid_to_string uid =
  uid |> Uid.to_int |> Char.chr |> String.make 1

let model_to_string uid_map_to_string =
  uid_map_to_string
  |> Uid.Map.bindings
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
  : (bool, 'k) Formula.t list * bool Uid.Map.t =
  let rec propagate clauses truth_tbl =
    match find_first_unit_literal clauses with
    | None -> clauses, truth_tbl
    | Some (key, value) ->
      let clauses_anded = Formula.and_ clauses in
      let uid = Symbol.to_uid key in
      let next_truthtbl = (Uid.Map.add uid value truth_tbl) in
      let next = Formula.subst value key clauses_anded in
      match next with
      | And next_ls -> 
        propagate next_ls next_truthtbl
      | rest ->
        [rest], next_truthtbl
  in 
  propagate clauses Uid.Map.empty

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

let is_falsified_clause (model_state : bool Uid.Map.t) (vars : (Uid.Set.t)) : bool =
  vars
  |> Uid.Set.for_all (
    fun symbol -> 
    match Uid.Map.find_opt symbol model_state with
    | None -> false
    | Some v -> not v
  )

let dpll 
  ?(leftovers : Uid.t -> bool = fun _ -> Random.self_init (); Random.bool ())
  (clauses : (bool, 'k) Formula.t list) 
  : 'k Solution.t =
  let all_keys = clauses |> Formula.and_ |> Formula.symbols in
  let rec dpll clauses model_state =
    let symbols = clauses |> List.map Formula.symbols in
    if
    symbols
      |> List.exists (is_falsified_clause model_state)
    then Solution.Unsat
    else
      let is_sat = (
        symbols
        |> List.for_all (fun uids ->
          uids
          |> Uid.Set.exists (fun uid -> 
            match Uid.Map.find_opt uid model_state with
            | None -> false
            | Some v -> v
          )
        )
      ) in
      if is_sat then 
        let diffed = 
          model_state
          |> Uid.Map.domain
          |> Uid.Set.diff all_keys 
        in
        let final_model = Uid.Map.add_seq (
          diffed
          |> Uid.Set.to_seq
          |> Seq.map (fun key -> key, leftovers key)
        ) model_state in
        Solution.Sat (Model.of_local (get_domain final_model) ~lookup:(fun uid -> Uid.Map.find_opt uid final_model))
      else
        let reduced, model = (
          clauses
          |> unit_propagate
          |> fun (e, partial) -> 
          e, 
          model_state 
          |> Uid.Map.union (fun _ _ new_v -> Some new_v) partial
        ) in
        match reduced with
        | [] -> Solution.Sat (
          Model.of_local (get_domain model) ~lookup:(fun uid -> Uid.Map.find_opt uid model)
        )
        | clauses when 
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
              ~lookup:(fun uid -> Uid.Map.find_opt uid model)
          in
          Solution.Sat solution_model
        | ls when List.exists (function Formula.Const_bool false -> true | _ -> false) ls -> Solution.Unsat
        | next ->
          let branch_key = choose_literal next in
          let uid = Symbol.to_uid branch_key in 
          let left_model = (Uid.Map.add uid true model) in
          match dpll next left_model with
          | Solution.Sat left_model -> 
            Solution.Sat left_model
          | Solution.Unsat ->
            let right_model = (Uid.Map.add uid false model) in
            dpll next right_model
          | Solution.Unknown -> raise (Should_not_happen "unknown solution")
  in
  dpll clauses Uid.Map.empty
;;

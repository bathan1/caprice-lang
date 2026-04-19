exception Should_not_happen of string

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
      | _ -> raise (Should_not_happen "lol")
    )

let unit_propagate 
  (clauses : (bool, 'k) Formula.t list) 
  : (bool, 'k) Formula.t list * 'a Model.t =
  let clauses_anded = Formula.and_ clauses in
  let truth_tbl = 
    clauses_anded
    |> Formula.count 
    |> Hashtbl.create
  in
  let rec propagate clauses =
    match find_first_unit_literal clauses  with
    | None -> clauses
    | Some (key, value) ->
      key 
      |> (function | (B uid) -> Hashtbl.add truth_tbl uid value);
      let next = Formula.subst value key clauses_anded in
      match next with
      | And next_ls -> propagate next_ls
      | rest -> [rest]
  in 
  let next_clauses = propagate clauses in
  let truth_tbl_model = 
    truth_tbl
    |> Hashtbl.to_seq_keys
    |> List.of_seq
    |> Model.of_local ~lookup:(fun uid -> Hashtbl.find_opt truth_tbl uid)
  in
  next_clauses, truth_tbl_model

let choose_literal (clauses : (bool, 'k) Formula.t list) 
  : (bool, 'k) Symbol.t =
  let get_symbol_exn =
    function
    | Formula.Key symbol -> symbol
    | _ -> raise (Should_not_happen "lol")
  in
  let is_key =
    function
    | Formula.Key _ -> true
    | _ -> false
  in
  let rec find_first_key (clauses : (bool, 'k) Formula.t list) : (bool, 'k) Symbol.t option =
    match clauses with
    | [] -> None
    | hd :: xs ->
      if is_key hd then
        Some (get_symbol_exn hd)
      else
        match hd with
        | Formula.Const_bool _ -> find_first_key xs
        | Formula.Not f -> find_first_key [f]
        | Formula.Binop (_, l, r) -> (
          match find_first_key [l] with
          | Some s -> Some s
          | None -> find_first_key []
        )
          
  in
  find_first_key clauses

let rec dpll (clauses : (bool, 'k) Formula.t list) : bool =
  let formula_to_clauses =
    function
    | Formula.And ls -> ls
    | e -> [e]
  in
  let reduced, _ = unit_propagate clauses in
  match reduced with
  | [] -> true
  | ls when List.exists (function Formula.Const_bool false -> true | _ -> false) ls -> false
  | next ->
    let branch_key = choose_literal next in
    let next_anded = Formula.and_ next in
    let try_value v = Formula.subst v branch_key next_anded in
    let left = 
      try_value true
      |> formula_to_clauses 
    in
    if dpll left then true
    else
      let right = 
        try_value false
        |> formula_to_clauses
      in dpll right

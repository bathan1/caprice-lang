open Utils

module UF = struct
  type t =
    { parent : (Theory.Shared.t, Theory.Shared.t) Hashtbl.t
    ; rank : (Theory.Shared.t, int) Hashtbl.t
    }

  let create () =
    { parent = Hashtbl.create 32
    ; rank = Hashtbl.create 32
    }

  let add uf x =
    if not (Hashtbl.mem uf.parent x) then begin
      Hashtbl.add uf.parent x x;
      Hashtbl.add uf.rank x 0
    end

  let rec find uf x =
    add uf x;
    let p = Hashtbl.find uf.parent x in
    if Theory.Shared.compare p x = 0 then
      x
    else begin
      let root = find uf p in
      Hashtbl.replace uf.parent x root;
      root
    end

  let union uf x y =
    let rx = find uf x in
    let ry = find uf y in
    if Theory.Shared.compare rx ry = 0 then
      ()
    else
      let rank_x = Hashtbl.find uf.rank rx in
      let rank_y = Hashtbl.find uf.rank ry in
      if rank_x < rank_y then
        Hashtbl.replace uf.parent rx ry
      else if rank_x > rank_y then
        Hashtbl.replace uf.parent ry rx
      else begin
        Hashtbl.replace uf.parent ry rx;
        Hashtbl.replace uf.rank rx (rank_x + 1)
      end

  let same uf x y =
    Theory.Shared.compare (find uf x) (find uf y) = 0

  let classes uf : Theory.Shared.t list list =
    let tbl = Hashtbl.create 32 in

    Hashtbl.iter
      (fun x _ ->
        let root = find uf x in
        let xs =
          match Hashtbl.find_opt tbl root with
          | Some xs -> xs
          | None -> []
        in
        Hashtbl.replace tbl root (x :: xs))
      uf.parent;

    tbl
    |> Hashtbl.to_seq_values
    |> List.of_seq
end

type merged_model =
  { uf : UF.t
  ; values : Model.value Theory.SharedMap.t
  }

let find_merged_opt
    (model : merged_model)
    (shared : Theory.Shared.t)
  : Model.value option =
  let rep = UF.find model.uf shared in
  Theory.SharedMap.find_opt rep model.values

let value_of_const : Theory.Shared.t -> Model.value option =
  function
  | Theory.Shared.Int_const i -> Some (Model.Int i)
  | Theory.Shared.Bool_const b -> Some (Model.Bool b)
  | Theory.Shared.Int_var _
  | Theory.Shared.Bool_var _ -> None

let find_shared_opt
    (model : 'k Model.t)
    (shared : Theory.Shared.t)
  : Model.value option =
  match shared with
  | Theory.Shared.Int_var uid ->
    model.value (I uid)
    |> Option.map (fun v -> Model.Int v)
  | Theory.Shared.Bool_var uid -> 
    model.value (B uid)
    |> Option.map (fun v -> Model.Bool v)
  | Theory.Shared.Int_const i ->
      Some (Int i)
  | Theory.Shared.Bool_const b ->
      Some (Bool b)

let value_from_models
    ~(models : 'k Model.t list)
    (members : Theory.Shared.t list)
  : Model.value option =
  members
  |> List.find_map (fun shared ->
       models
       |> List.find_map (fun model ->
            find_shared_opt model shared))

let merge_models
    ~(arrangement : 'k Theory.literal list)
    ~(models : 'k Model.t list)
  : merged_model =
  let uf = UF.create () in

  (* Add every variable appearing in every theory model as a singleton UF class. *)
  List.iter
    (fun (model : 'k Model.t) ->
      List.iter
        (fun key ->
          let shared =
            match key with
            | Model.Int_key uid -> Theory.Shared.Int_var uid
            | Model.Bool_key uid -> Theory.Shared.Bool_var uid
          in
          UF.add uf shared)
        model.domain)
    models;

  (* Union positive interface equalities from SAT's guessed arrangement. *)
  List.iter
    (function
      | Theory.Pos (Theory.Predicate (Binop.Equal, left, right)) ->
          begin match
            Theory.Shared.from_formula left,
            Theory.Shared.from_formula right
          with
          | Some x, Some y ->
              UF.union uf x y
          | _ ->
              ()
          end

      | _ ->
          ())
    arrangement;

  let value_of_const = function
    | Theory.Shared.Int_const i -> Some (Model.Int i)
    | Theory.Shared.Bool_const b -> Some (Model.Bool b)
    | Theory.Shared.Int_var _
    | Theory.Shared.Bool_var _ -> None
  in

  let value_from_model
      (model : 'k Model.t)
      (shared : Theory.Shared.t)
    : Model.value option =
    match shared with
    | Theory.Shared.Int_var uid -> (
        match model.value (Symbol.I uid) with
        | Some i -> Some (Model.Int i)
        | None -> None)

    | Theory.Shared.Bool_var uid -> (
        match model.value (Symbol.B uid) with
        | Some b -> Some (Model.Bool b)
        | None -> None)

    | Theory.Shared.Int_const i ->
        Some (Model.Int i)

    | Theory.Shared.Bool_const b ->
        Some (Model.Bool b)
  in

  let value_from_models
      (members : Theory.Shared.t list)
    : Model.value option =
    members
    |> List.find_map (fun shared ->
         models
         |> List.find_map (fun model ->
              value_from_model model shared))
  in

  let values =
    UF.classes uf
    |> List.fold_left
         (fun acc members ->
           match members with
           | [] ->
               acc

           | hd :: _ ->
               let rep = UF.find uf hd in

               let chosen =
                 match List.find_map value_of_const members with
                 | Some value -> Some value
                 | None -> value_from_models members
               in

               match chosen with
               | Some value ->
                   Theory.SharedMap.add rep value acc
               | None ->
                   acc)
         Theory.SharedMap.empty
  in

  { uf; values }

let to_model (merged : merged_model) : 'k Model.t =
  let value_map =
    UF.classes merged.uf
    |> List.fold_left
         (fun acc members ->
           match members with
           | [] ->
               acc

           | hd :: _ ->
               let rep = UF.find merged.uf hd in

               begin match Theory.SharedMap.find_opt rep merged.values with
               | None ->
                   acc

               | Some value ->
                   List.fold_left
                     (fun acc member ->
                       match member with
                       | Theory.Shared.Int_var uid
                       | Theory.Shared.Bool_var uid ->
                           Model.ValueMap.add uid value acc

                       | Theory.Shared.Int_const _
                       | Theory.Shared.Bool_const _ ->
                           acc)
                     acc
                     members
               end)
         Model.ValueMap.empty
  in

  Model.from_value_map value_map

let accepts : 'k Theory.literal -> bool =
  let is_euf_term : type a k. (a, k) Formula.t -> bool =
    function
    | Formula.Key (Symbol.I _) -> true
    | Formula.Const_int _ -> true
    | _ -> false
  in
  let accepts_atom : 'k Theory.atom -> bool =
    function
    | Theory.Predicate (Binop.Equal, l, r) -> is_euf_term l && is_euf_term r
    | _ -> false
  in
  function
  | Theory.Pos atom
  | Theory.Neg atom -> accepts_atom atom

let constant_conflict uf =
  let classes =
    Hashtbl.fold
      (fun term _ acc ->
        let root = UF.find uf term in
        let old =
          match Theory.SharedMap.find_opt root acc with
          | Some xs -> xs
          | None -> []
        in
        Theory.SharedMap.add root (term :: old) acc)
      uf.UF.parent
      Theory.SharedMap.empty
  in
  Theory.SharedMap.to_seq classes
  |> Seq.find_map
    (fun (_root, terms) ->
      let int_consts =
        terms
        |> List.filter_map (function
            | Theory.Shared.Int_const i -> Some i
            | _ -> None)
        |> List.sort_uniq Int.compare
      in
      let bool_consts =
        terms
        |> List.filter_map (function
            | Theory.Shared.Bool_const b -> Some b
            | _ -> None)
        |> List.sort_uniq Bool.compare
      in

      match int_consts, bool_consts with
      | _ :: _ :: _, _ -> Some ()
      | _, _ :: _ :: _ -> Some ()
      | _ -> None)

type 'k eq_lit =
  | Eq of Theory.Shared.t * Theory.Shared.t * 'k Theory.literal
  | Neq of Theory.Shared.t * Theory.Shared.t * 'k Theory.literal

let int_value_of_term = function
  | Theory.Shared.Int_const i -> Some i
  | _ -> None

let bool_value_of_term = function
  | Theory.Shared.Bool_const b -> Some b
  | _ -> None

let root_equal uf root term =
  Theory.Shared.compare root (UF.find uf term) = 0

let forbidden_int_values eq_lits uf root =
  eq_lits
  |> List.filter_map (function
       | Neq (l, r, _) ->
           if root_equal uf root l then
             int_value_of_term r
           else if root_equal uf root r then
             int_value_of_term l
           else
             None

       | Eq _ ->
           None)
  |> List.sort_uniq Int.compare

let forbidden_bool_values eq_lits uf root =
  eq_lits
  |> List.filter_map (function
       | Neq (l, r, _) ->
           if root_equal uf root l then
             bool_value_of_term r
           else if root_equal uf root r then
             bool_value_of_term l
           else
             None

       | Eq _ ->
           None)
  |> List.sort_uniq Bool.compare

let choose_int_value forbidden =
  let rec loop i =
    if List.mem i forbidden then
      loop (i + 1)
    else
      i
  in
  loop 0

let choose_bool_value forbidden =
  if not (List.mem false forbidden) then
    Some false
  else if not (List.mem true forbidden) then
    Some true
  else
    None

let eq_lit_of_theory_lit
  (lit : 'k Theory.literal)
  : 'k eq_lit option =
  match lit with
  | Theory.Pos (Theory.Predicate (Binop.Equal, left, right)) ->
    begin match Theory.Shared.from_formula left, Theory.Shared.from_formula right with
    | Some l, Some r -> Some (Eq (l, r, lit))
    | _ -> None
    end
  | Theory.Neg (Theory.Predicate (Binop.Equal, left, right)) ->
    begin match Theory.Shared.from_formula left, Theory.Shared.from_formula right with
    | Some l, Some r -> Some (Neq (l, r, lit))
    | _ -> None
    end
  | _ -> None

let class_terms uf root =
  Hashtbl.fold
    (fun term _ acc ->
      if Theory.Shared.compare (UF.find uf term) root = 0 then term :: acc else acc)
    uf.UF.parent
    []

let class_int_value uf root =
  class_terms uf root
  |> List.find_map (function
       | Theory.Shared.Int_const i -> Some i
       | _ -> None)

let class_bool_value uf root =
  class_terms uf root
  |> List.find_map (function
       | Theory.Shared.Bool_const b -> Some b
       | _ -> None)

let model_from_uf eq_lits uf =
  let bindings =
    Hashtbl.fold
      (fun term _ acc ->
        match term with
        | Theory.Shared.Int_var uid ->
            let root = UF.find uf term in
            let value =
              match class_int_value uf root with
              | Some i ->
                  i
              | None ->
                  root
                  |> forbidden_int_values eq_lits uf
                  |> choose_int_value
            in
            Model.ValueMap.add_int uid value acc

        | Theory.Shared.Bool_var uid ->
            let root = UF.find uf term in
            let value =
              match class_bool_value uf root with
              | Some b ->
                  b
              | None ->
                  begin match
                    root
                    |> forbidden_bool_values eq_lits uf
                    |> choose_bool_value
                  with
                  | Some b -> b
                  | None -> false
                  end
            in
            Model.ValueMap.add_bool uid value acc

        | Int_const _
        | Bool_const _ ->
            acc)
      uf.UF.parent
      Uid.Map.empty
  in
  Model.from_value_map bindings

let terms_of_uf (uf : UF.t) : Theory.Shared.t list =
  Hashtbl.fold
    (fun term _ acc -> term :: acc)
    uf.UF.parent
    []

let all_pairs xs =
  let rec aux acc = function
    | [] -> acc
    | x :: rest ->
        let pairs = List.map (fun y -> (x, y)) rest in
        aux (pairs @ acc) rest
  in
  aux [] xs

let implied_equalities_from_uf (uf : UF.t) : (Theory.Shared.t * Theory.Shared.t) list =
  uf
  |> terms_of_uf
  |> all_pairs
  |> List.filter (fun (l, r) -> UF.same uf l r)

let disequalities_from_lits eq_lits =
  eq_lits
  |> List.filter_map (function
       | Neq (l, r, original_lit) -> Some (l, r, original_lit)
       | Eq _ -> None)

let uf_from_eq_lits (eq_lits : 'k eq_lit list) : UF.t =
  let uf = UF.create () in
  List.iter
    (function
      | Eq (l, r, _) | Neq (l, r, _) ->
          UF.add uf l;
          UF.add uf r)
    eq_lits;
  List.iter
    (function
      | Eq (l, r, _) -> UF.union uf l r
      | Neq _ -> ())
    eq_lits;
  uf

let implied_equalities (formula : 'k Theory.literal list) : (Theory.Shared.t * Theory.Shared.t) list =
  let eq_lits = List.filter_map eq_lit_of_theory_lit formula in
  if List.length eq_lits <> List.length formula then
    []
  else
    let uf = uf_from_eq_lits eq_lits in
    implied_equalities_from_uf uf

let disequalities (formula : 'k Theory.literal list)
  : (Theory.Shared.t * Theory.Shared.t * 'k Theory.literal) list =
  disequalities_from_lits @@ List.filter_map eq_lit_of_theory_lit formula

let solve (formula : 'k Theory.literal list) : 'k Theory.t_solution =
  let eq_lits = List.filter_map eq_lit_of_theory_lit formula in
  let uf = uf_from_eq_lits eq_lits in
  match constant_conflict uf with
  | Some () ->
      Theory.Theory_unsat formula
  | None ->
    begin match List.find_opt
      (function
        | Neq (l, r, _) -> UF.same uf l r
        | Eq _ -> false)
      eq_lits
    with
    | Some (Neq (_, _, original_lit)) -> Theory.Theory_unsat [original_lit]
    | Some (Eq _) -> assert false
    | None -> Theory.Theory_sat (model_from_uf eq_lits uf)
  end

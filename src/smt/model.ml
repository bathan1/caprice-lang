open Utils

type 'k key =
  | Bool_key : (bool, 'k) Symbol.t -> 'k key
  | Int_key : (int, 'k) Symbol.t -> 'k key

type 'k t =
  { value : 'a. ('a, 'k) Symbol.t -> 'a option
  ; domain : 'k key list }

let merge (s1 : 'k t) (s2 : 'k t) : 'k t =
  let value (type a) (sym : (a, 'k) Symbol.t) : a option =
    match s1.value sym with
    | None -> s2.value sym
    | v -> v
  in
  { value ; domain = s1.domain @ s2.domain }

let empty : 'k t = { value = (fun _ -> None) ; domain = [] }

let singleton (type a) (a : a) (s : (a, 'k) Symbol.t) : 'k t =
  let value (type b) (s' : (b, 'k) Symbol.t) : b option =
    match s, s' with
    | I uid, I uid' when Uid.equal uid uid' -> Some a
    | B uid, B uid' when Uid.equal uid uid' -> Some a
    | _ -> None
  in
  let single_key = 
    match s with
    | (I _) as key -> Int_key key
    | (B _) as key -> Bool_key key
  in
  { value ; domain = [single_key] }


type value =
  | Bool of bool
  | Int of int

(** [from_value_map map] wraps [Uid.t]-keyed MAP with Model.t.

    {[
    module IntMap = Map.Make (Int)
    let () =
      let int_map = (
        IntMap.empty
        |> Map.add_exn ~key:(Char.to_int 'a') ~data:(Int 0)
        |> Map.add_exn ~key:(Char.to_int 'b') ~data:(Int 1)
      ) in
        let pp_model = Model.to_string ~sep:("; ") ~pp_assignment:(
          fun (I x) v -> sprintf " %c => %s" (Char.of_int_exn x) (
            if v = 0 then "hello" else "world"
          )
        ) in
        let model = Model.from_value_map int_map in
        pp_model model [a; b;]
        |> printf "From local: %s\n";
    ]}

    This prints:

    {["From local: { a => hello; b => world }"]}
*)
let from_value_map (map : value Uid.Map.t) : 'k t =
  let domain =
    map
    |> Uid.Map.to_list
    |> List.map (fun (uid, v) ->
        match v with
        | Bool _ -> Bool_key (Symbol.B uid)
        | Int _ -> Int_key (Symbol.I uid))
  in
  { domain
  ; value =
      (fun (type a) (sym : (a, 'k) Symbol.t) : a option ->
        match sym with
        | B key -> (
            match Uid.Map.find_opt key map with
            | Some (Bool b) -> Some b
            | _ -> None)

        | I key -> (
            match Uid.Map.find_opt key map with
            | Some (Int i) -> Some i
            | _ -> None))
  }

let to_string
  (type k)
  (model : k t)
  ~(key : k key -> string)
  : string =
  let indent = "  " in
  let entry_to_string : type a. (a, k) Symbol.t -> string -> a -> string =
    fun symbol text v ->
      match symbol with
      | Symbol.B _ ->
        Printf.sprintf "%s\"%s\": %s"
          indent
          text
          (Bool.to_string v)
      | Symbol.I _ ->
        Printf.sprintf "%s\"%s\": %d"
          indent
          text
          v
  in
  let entries =
    model.domain
    |> List.filter_map (fun map_key ->
      match map_key with
      | Bool_key symbol -> (
          let text = key map_key in
          match model.value symbol with
          | None -> None
          | Some v -> Some (entry_to_string symbol text v))
      | Int_key symbol -> (
          let text = key map_key in
          match model.value symbol with
          | None -> None
          | Some v -> Some (entry_to_string symbol text v)))
  in

  match entries with
  | [] -> "{\n}"
  | _ -> "{\n" ^ String.concat ",\n" entries ^ "\n}"

let pp_key
  (type k)
  ~(key : k key -> string)
  (fmt : Format.formatter)
  (model : k t)
  : unit =
  let pp_entry : type a. (a, k) Symbol.t -> string -> a -> unit =
    fun symbol text v ->
      match symbol with
      | Symbol.B _ ->
        Format.fprintf fmt "@[<h>\"%s\": %s@]"
          text
          (Bool.to_string v)

      | Symbol.I _ ->
        Format.fprintf fmt "@[<h>\"%s\": %d@]"
          text
          v
  in

  let entries =
    model.domain
    |> List.filter_map (fun map_key ->
      match map_key with
      | Bool_key symbol ->
        let text = key map_key in
        begin
          match model.value symbol with
          | None -> None
          | Some v -> Some (fun () -> pp_entry symbol text v)
        end

      | Int_key symbol ->
        let text = key map_key in
        begin
          match model.value symbol with
          | None -> None
          | Some v -> Some (fun () -> pp_entry symbol text v)
        end)
  in

  match entries with
  | [] ->
    Format.fprintf fmt "{@,}"

  | _ ->
    Format.fprintf fmt "{@[<v 2>@,";
    List.iteri
      (fun i pp_entry ->
        if i > 0 then Format.fprintf fmt ",@,";
        pp_entry ())
      entries;
    Format.fprintf fmt "@]@,}"

open Utils

type 'k t =
  { 
    value : 'a. ('a, 'k) Symbol.t -> 'a option;
    domain : Uid.t list; 
  }

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
  { value ; domain = [ match s with (I uid | B uid) -> uid ] }

(** [of_local domain ~lookup] (unsafely) casts DOMAIN and LOOKUP function into a [Model.t]

    LOOKUP is passed in the [Uid.t] of a formula key and should return 
    an [option] of whatever value LOCAL holds for the given uid.

    {2 From an {!Int.Map} local solution}

    Local solutions that use some kind of a {!Map} map nicely to
    to the 'global' {!t}:

    {[
    module IntMap = Map.Make (Int)
    let () =
      let int_map = (
        IntMap.empty
        |> Map.add_exn ~key:(Char.to_int 'a') ~data:0
        |> Map.add_exn ~key:(Char.to_int 'b') ~data:1
      ) in
        let pp_model = Model.to_string ~sep:("; ") ~pp_assignment:(
          fun (I x) v -> sprintf " %c => %s" (Char.of_int_exn x) (
            if v = 0 then "hello" else "world"
          )
        ) in
        let model = Model.of_local int_map ~lookup:Map.find in
        pp_model model [a; b;]
        |> printf "From local: %s\n";
    ]}

    This prints:

    {["From local: { a => hello; b => world }"]}
*)

type value =
  | Bool of bool
  | Int of int

let from_value_map (map : value Uid.Map.t) =
  let bindings = Uid.Map.to_list map in
  let domain = List.map (fun (key, _) -> key) bindings in
  {
    domain;
    value =
      (fun (type a) (sym : (a, 'k) Symbol.t) : a option ->
        match sym with
        | B key ->
            begin match Uid.Map.find_opt key map with
            | Some (Bool b) -> Some b
            | _ -> None
            end
        | I key ->
            begin match Uid.Map.find_opt key map with
            | Some (Int i) -> Some i
            | _ -> None
            end
      );
  }

let to_string
  (type a k)
  (model : k t)
  ~(uid : Uid.t -> (a, k) Symbol.t * string)
  : string =
  let indent = "  " in
  let entry_to_string : type a. (a, k) Symbol.t -> string -> a -> string =
    fun symbol text v ->
      match symbol with
      | Symbol.B _ ->
        Printf.sprintf "%s\"%s\": %s"
          indent
          text
          (if v then "true" else "false")
      | Symbol.I _ ->
        Printf.sprintf "%s\"%s\": %d"
          indent
          text
          v
  in
  let entries =
    model.domain
    |> List.filter_map (fun key ->
      let symbol, text = uid key in
      match model.value symbol with
      | None -> None
      | Some v -> Some (entry_to_string symbol text v)
    )
  in
  match entries with
  | [] -> "{\n}"
  | _ ->
    "{\n"
    ^ String.concat ",\n" entries
    ^ "\n}"


type 'k t = 
  { value : 'a. ('a, 'k) Symbol.t -> 'a option
  ; domain : Utils.Uid.t list }

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
    | I uid, I uid' when Utils.Uid.equal uid uid' -> Some a
    | B uid, B uid' when Utils.Uid.equal uid uid' -> Some a
    | _ -> None
  in
  { value ; domain = [ match s with (I uid | B uid) -> uid ] }

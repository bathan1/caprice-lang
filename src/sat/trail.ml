open Formula

type reason =
  | Decided
  | Propagated of literal list

let pp_reason ~uid fmt =
  function
  | Decided -> Format.fprintf fmt "Decided"
  | Propagated clause ->
      Format.fprintf fmt "Propagated(%a)" (Formula.pp_clause ~uid) clause

type t = { level : int ; lit : literal ; reason : reason }

let pp_trail ~uid fmt (trail : t list) : unit =
  let n = List.length trail in
  Format.fprintf fmt "[";
  List.iteri
    (fun i t ->
      Format.fprintf fmt
        "{ \"level\": %d, \"lit\": %a, \"reason\": %a }%s"
    t.level (Formula.pp_literal ~uid) t.lit
    (pp_reason ~uid) t.reason
    (if i < n - 1 then "," else ""))
    trail;
  Format.fprintf fmt "]"

(** [find_opt lit trail] returns the entry from TRAIL with LIT *)
let find_opt (lit : literal) (trail : t list) : t option =
  List.find_opt (fun entry -> key_from_lit entry.lit = key_from_lit lit) trail

(** [find_level lit trail] returns the decision level of LIT in TRAIL or throws if LIT doesn't exist in TRAIL *)
let find_level (lit : literal) (trail : t list) : int =
  match find_opt lit trail with
  | None -> failwith "level_of_lit: literal is not assigned!"
  | Some entry -> entry.level

(** [to_model trail] derives the boolean value list of each literal from TRAIL *)
let to_model (trail : t list) : literal list =
  List.map (fun entry -> entry.lit) trail

(** [find_propagated_opt lits trail] returns the first literal in LITS that exists in TRAIL *and* has [reason = Propagated] *)
let find_propagated_opt (lits : literal list) (trail : t list) =
  List.find_opt 
    (fun lit ->
      match find_opt lit trail with
      | Some { reason = Propagated _; _ } -> true
      | _ -> false)
      lits

(** [find_propagated lits trail] returns the first literal in LITS that exists in TRAIL *and* has [reason = Propagated] if it exists otherwise it throws *)
let find_propagated (lits : literal list) (trail : t list) : literal =
  match find_propagated_opt lits trail with
  | None -> failwith "that trail doesn't have any propagated literals!"
  | Some lit -> lit

(** [find_reason_opt lits trail] returns the reason clause of the
    first propagated literal from LITS in TRAIL, or throws if that doesn't exist *)
let find_reason_opt (lits : literal list) (trail : t list) : literal list option =
  List.find_map
    (fun lit ->
      match find_opt lit trail with
      | Some { reason = Propagated reason_clause; _ } -> Some reason_clause
      | _ -> None)
      lits

(** [find_propagated_reason lits trail] returns the first literal in LITS that exists in TRAIL *and* has 
    [reason = Propagated] if it exists otherwise it throws *)
let find_reason (lits : literal list) (trail : t list) : literal list =
  match find_reason_opt lits trail with
  | Some clause -> clause
  | None ->
    failwith
      (Format.asprintf
        "no propagated literal from LITS in TRAIL\nlits = %a\ntrail = %a"
        (Formula.pp_clause ~uid:(fun uid -> Int.to_string @@ Utils.Uid.to_int uid)) lits
        (pp_trail ~uid:(fun uid -> Int.to_string @@ Utils.Uid.to_int uid)) trail)

(** [backtrack backtrack_level trail] returns a new trail list where all elements
    with [level > BACKTRACK_LEVEL] are popped *)
let backtrack (backtrack_level : int) (trail : t list) : t list =
  List.filter (fun { level; _ } -> level <= backtrack_level) trail

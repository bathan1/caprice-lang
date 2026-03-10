
(*
  This file copies the parts of the Semantics module that are needed
  to trace errors.
*)

open Lang
open Grammar

exception InvariantException of string

module State = struct
  type t = 
    { lazies : Val.vlazy Suspension.Map.t
    ; detfun_alists : Val.alist Suspension.Map.t
    }

  let empty : t =
    { lazies = Suspension.Map.empty
    ; detfun_alists = Suspension.Map.empty
    }
end

module Context = struct
  type det_context =
    | Allowed
    | Disallowed

  type t = { det_context : det_context } [@@unboxed]
end

include Monad

type 'env with_env = < err : Eval_result.t ; env : 'env ; state : State.t ; ctx : Context.t >
type ('a, 'env) m = ('a, 'env with_env) t

module Matches = Val.Make_match (struct
  type nonrec 'a m = ('a, Val.Env.t) m
  include (Monad : Utils.Types.MONAD with type 'a m := 'a m)
end)

let[@inline always] incr_step : 'env. (unit, 'env) m = 
  { run = fun ~reject ~accept state step _ _ ->
    accept () state (Step.next step)
  }

(**
  [fetch id] is the value associated with [id] in the environment,
    or failure if [id] is unbound.
*)
let[@inline always] fetch (id : Ident.t) : (Val.any, Val.Env.t) m =
  { run = fun ~reject ~accept state step env _ ->
      match Env.find id env with
      | None -> reject (Eval_result.Unbound_variable id) state
      | Some v -> accept v state step
  }

(* For typing purposes (due to value restriction), we must inline the
  definition of `M.escape`.
    
  The ideal implementation would simply be `escape Vanish`.
*)
let vanish : 'a 'env. ('a, 'env) m =
  { run = fun ~reject ~accept:_ state _ _ _ -> reject Vanish state }

let mismatch : 'a 'env. string -> ('a, 'env) m = fun msg ->
  escape (Eval_result.Mismatch msg)

(**
  [assert_inputs_allowed] is a failure if the context disallows inputs.
*)
let assert_inputs_allowed : 'env. (unit, 'env) m =
  { run = fun ~reject ~accept state step _ ctx ->
    match ctx.det_context with
    | Allowed -> accept () state step
    | Disallowed -> reject (Mismatch "Nondeterminism used when not allowed") state
  }

(**
  [read_input kind input_env] is then input from [input_env] with the
    kind [kind], read from the current time.
*)
let read_input_exn (kind : 'a Input.Kind.t) (input_env : Input_env.t) : ('a, 'env) m =
  let* () = assert_inputs_allowed in
  let* step = step in
  let a_opt = Input_env.find kind (Stepkey step) input_env in
  return (Option.get a_opt)

type 'a suspension_kind =
  | SLazy : Val.vlazy suspension_kind
  | SAlist : Val.alist suspension_kind

let read_cell : type a env. a suspension_kind -> a Suspension.t -> (a, env) m =
  fun kind susp ->
    let* (s : State.t) = get in
    let map : a Suspension.Map.t =
      match kind with
      | SLazy -> s.lazies
      | SAlist -> s.detfun_alists
    in
    return (Suspension.Map.find_exn susp map)

let set_cell : type a env. a suspension_kind -> a Suspension.t -> a -> (unit, env) m =
  fun kind susp v ->
    modify (fun (s : State.t) ->
      match kind with
      | SLazy -> { s with lazies = Suspension.Map.add susp v s.lazies}
      | SAlist -> { s with detfun_alists = Suspension.Map.add susp v s.detfun_alists}
    )

(* Because of value restriction, we must inline this definition. We would prefer to write
      let* Step id = step in
      let susp = { Suspension.id } in
      let* () = set_cell SAlist { id } [] in
      return susp
*)
let make_alist : 'env. (Val.alist Suspension.t, 'env) m =
  { run = fun ~reject:_ ~accept state step _ _ ->
    let Step id = step in
    let susp = { Suspension.id } in
    accept susp { state with detfun_alists =
      Suspension.Map.add susp [] state.detfun_alists } step
  }

let make_lazy : 'env. Val.lgen -> (Val.dval, 'env) m = fun lgen ->
  let* Step id = step in
  let v = Val.VLazy { cell = { id } ; wrapping_types = [] } in
  let* () = set_cell SLazy { id } (Val.LLazy lgen) in
  return v

(**
  [disallow_inputs x] runs [x] such that any [assert_inputs_allowed]
    is a failure.
*)
let[@inline always] disallow_inputs (x : ('a, 'env) m) : ('a, 'env) m =
  local_ctx (fun _ -> { Context.det_context = Disallowed }) x

(**
  [allow_inputs x] runs [x] such that any [assert_inputs_allowed]
    is NOT a failure.
*)
let[@inline always] allow_inputs (x : ('a, 'env) m) : ('a, 'env) m =
  local_ctx (fun _ -> { Context.det_context = Allowed }) x

(**
  [run x target] runs [x] with [target] as the context, beginning with
    empty state and environment.
*)
let run (x : ('a, Val.Env.t) m) : Eval_result.t =
  match run x State.empty Env.empty { det_context = Allowed } with
  | Ok _, _ -> Done
  | Error e, _ -> e


open Lang
open Grammar

exception InvariantException of string

module State = struct
  type t =
    { rev_stem : Rev_stem.t (* we will cons to the path instead of union a log *)
    ; logged_inputs : Input_env.t
    ; runs : Logged_run.t list
    ; lazies : Val.vlazy Suspension.Map.t
    ; detfun_alists : Val.alist Suspension.Map.t
    }

  let empty : t =
    { rev_stem = Rev_stem.empty
    ; logged_inputs = Input_env.empty
    ; runs = []
    ; lazies = Suspension.Map.empty
    ; detfun_alists = Suspension.Map.empty
    }
end

module Context = struct
  type det_context =
    | Allowed
    | Disallowed

  type t =
    { target : Target.t
    ; det_context : det_context }
end

include Monad

type ('a, 'env) m = ('a, < err : Eval_result.t ; env : 'env ; state : State.t ; ctx : Context.t >) t

module Matches = Val.Make_match (struct
  type nonrec 'a m = ('a, Val.Env.t) m
  include (Monad : Utils.Types.MONAD with type 'a m := 'a m)
end)

let[@inline] incr_step
  : 'env. max_step:Step.t -> (unit, 'env) m
  = fun ~max_step ->
  { run = fun ~reject ~accept state step _ _ ->
      let step = Step.next step in
      if Step.(step > max_step)
      then reject (Eval_result.Reach_max_step step) state
      else accept () state step
  }

(**
  [fetch id] is the value associated with [id] in the environment,
    or failure if [id] is unbound.
*)
let[@inline] fetch (id : Ident.t) : (Val.any, Val.Env.t) m =
  { run = fun ~reject ~accept state step env _ ->
      match Env.find id env with
      | None -> reject (Eval_result.Unbound_variable id) state
      | Some v -> accept v state step
  }

(* For typing purposes (due to value restriction), we must inline the
  definition of `Monad.escape`.

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
  [push_tag_to_path ?alternatives tag] pushes [tag] onto the path stem, and records
    the [alternatives] as the other inputs possible so that a target can be made
    from them.
*)
let push_tag_to_path ?(alternatives : Tag.t list = []) (tag : Tag.t) : (unit, 'env) m =
  let* step = step in
  let* { Context.target ; _ } = read_ctx in
  modify (fun (s : State.t) ->
    let path_item =
      Path_item.Tag { tag ; alternatives ; key =
        Stepkey step ; logged_inputs = s.logged_inputs }
    in
    let rev_stem =
      Rev_stem.cons path_item s.rev_stem ~if_exceeds:(Target.priority target)
    in
    { s with rev_stem }
  )

(**
  [log_input kind a] logs the input [a] with kind [kind] to have been
    read at the current time.
*)
let log_input (kind : 'a Input.Kind.t) (a : 'a) : (unit, 'env) m =
  let* step in
  modify (fun (s : State.t) ->
    { s with logged_inputs =
        Input_env.add kind (Stepkey step) a s.logged_inputs
    }
  )

(**
  [push_and_log_tag tag] pushes the [tag] to the path stem without alternatives
    and logs [tag] as the input. Both actions are with respect to the current
    time.
*)
let push_and_log_tag (tag : Tag.t) : (unit, 'env) m =
  let* () = push_tag_to_path tag in
  log_input KTag tag

(**
  [push_formula_to_path ?allow_flip formula] pushes the formula to the path stem
    as a true formula, such that any evaluation following the same path again must
    satifisfy the formula. By default, a target will be made from the negation
    of the formula, unless [allow_flip] is false.
*)
let push_formula_to_path ?(allow_flip : bool = true)
  (formula : (bool, Stepkey.t) Smt.Formula.t) : (unit, 'env) m =
  if Smt.Formula.is_const formula then
    return ()
  else
    let* { Context.target ; _ } = read_ctx in
    modify (fun (s : State.t) ->
      let path_item =
        if allow_flip then
          Path_item.Formula { cond = formula ; logged_inputs = s.logged_inputs }
        else
          Nonflipping formula
      in
      let rev_stem =
        Rev_stem.cons path_item s.rev_stem ~if_exceeds:(Target.priority target)
      in
      { s with rev_stem }
    )

(**
  [read_input kind input_env] is an optional input from [input_env] with the
    kind [kind], read from the current time. Does not log the input as read
    because the default behavior is to return [None], in which case there
    is no input to log.
*)
let read_input (kind : 'a Input.Kind.t) (input_env : Input_env.t) : ('a option, 'env) m =
  let* () = assert_inputs_allowed in
  let* step = step in
  return (Input_env.find kind (Stepkey step) input_env)

(**
  [read_and_log_input kind input_env ~default] is an input from [input_env]
    of the kind [kind], or [default] if the input was unplanned. Then, the
    input is logged as read from the environment, and it is returned.
*)
let read_and_log_input (kind : 'a Input.Kind.t) (input_env : Input_env.t)
  ~(default : 'a) : ('a, 'env) m =
  let* () = assert_inputs_allowed in
  let* step = step in
  let input =
    Option.value ~default (Input_env.find kind (Stepkey step) input_env)
  in
  let* () = log_input kind input in
  return input

(**
  [target_to_here] is a target representing the path to the current
    program point. It is trivial to solve because its solution is
    the logged input environment.

  Invariant: this should only be sequenced when the old target has been
    reached. It is asserted that this invariant holds
*)
let target_to_here : 'env. (Target.t, 'env) m =
  { run = fun ~reject:_ ~accept state step _ { target ; _ } ->
    assert (
      let n = state.rev_stem.total_priority in
      let n' = Target.priority target in
      Path_priority.geq n n'
    );
    accept (
      Target.make Formula.trivial
        (Formula.BSet.union target.all_formulas (Path.formulas state.rev_stem.rev_stem))
        state.logged_inputs
        ~path_priority:state.rev_stem.total_priority
    ) state step
  }

[@@@landmark "auto-off"]

(**
  [fork forked_m] runs [forked_m] with the current state, environment, and
    step count. If [forked_m] is a failure case, then the result is a failure.
    Otherwise, the original state is restored, and the fork is logged as a
    run.
    Calls [Utils.Time.yield_to_timer] because this is a good moment to check for
    time out. Therefore, this function must be run inside [Utils.Time.with_timeout]
    so that the effect is handled.
*)
let fork (forked_m : 'a. ('a, 'env) m) : (unit, 'env) m =
  let* { Context.det_context ; _ } = read_ctx in
  let* target = target_to_here in
  fork forked_m { target ; det_context }
    ~setup_state:
      (fun state ->
        (* keeps all the logged runs *)
        { state with rev_stem = Rev_stem.discard_stem state.rev_stem }
      )
    ~restore_state:
      (fun e ~og ~forked_state ->
        let forked_run =
          { Logged_run.rev_stem = forked_state.rev_stem
          ; target
          ; answer = Eval_result.to_answer e }
        in
        (* Note that the forked state runs include the original runs (see setup_state)
            so we will overwrite og runs; they are included inside forked_state.runs *)
        { og with runs = forked_run :: forked_state.runs }
      )
    (fun res ->
      if Eval_result.is_signal_to_stop res then
        escape res (* propagate up the failure *)
      else begin
        Utils.Time.yield_to_timer (); return ()
      end
    )

[@@@landmark "auto"]

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
  let* () = set_cell SLazy { id } (Val.LLazy lgen) in
  return (Val.VLazy { cell = { id } ; wrapping_types = [] })

(**
  [disallow_inputs x] runs [x] such that any [assert_inputs_allowed]
    is a failure.
*)
let[@inline] disallow_inputs (x : ('a, 'env) m) : ('a, 'env) m =
  local_ctx (fun (ctx : Context.t) -> { ctx with det_context = Disallowed }) x

(**
  [allow_inputs x] runs [x] such that any [assert_inputs_allowed]
    is NOT a failure.
*)
let[@inline] allow_inputs (x : ('a, 'env) m) : ('a, 'env) m =
  local_ctx (fun (ctx : Context.t) -> { ctx with det_context = Allowed }) x

(**
  [local_mode mode x] runs [x] in the context based on
    the [mode] of the function type that is being checked.

    The context disallows inputs if the mode is deterministic.
*)
let local_mode (mode : Funtype.mode) (x : ('a, 'env) m) : ('a, 'env) m =
  match mode with
  | Nondet -> x
  | Det -> disallow_inputs x

(**
  [run x target] runs [x] with [target] as the context, beginning with
    empty state and environment.
*)
let run (x : ('a, Val.Env.t) m) (target : Target.t) : Eval_result.t * State.t =
  match run x State.empty Env.empty { target ; det_context = Allowed } with
  | Ok _, state -> Done, state
  | Error e, state -> e, state


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

(*
  Make a monad out of the state and context and evaluation result.
  - Has stateful State as well as step count
  - Has a target as a context, and also a type parameter for the environment
  - The error type is from Eval_result
*)
module M = Monad.Make (State) (Context) (Eval_result)
include M

module Matches = Val.Make_match (struct
  type 'a m = ('a, Val.Env.t) M.m
  include (M : Utils.Types.MONAD with type 'a m := 'a m)
end)

(**
  [fetch id] is the value associated with [id] in the environment,
    or failure if [id] is unbound.
*)
let[@inline always] fetch (id : Ident.t) : (Val.any, Val.Env.t) m =
  { run = fun ~reject ~accept state step env _ ->
      match Env.find id env with
      | None -> let e, s = Eval_result.fail_on_fetch id state in reject e s
      | Some v -> accept v state step
  }

(* For typing purposes (due to value restriction), we must inline the
  definition of `M.escape`.
    
  The ideal implementation would simply be `escape Vanish`.
*)
let vanish : 'a 'env. ('a, 'env) m =
  { run = fun ~reject ~accept:_ state _ _ _ -> reject Vanish state }

let mismatch : 'a 'env. string -> ('a, 'env) m = fun msg ->
  escape (Mismatch msg)

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
  let* { target ; _ } = read_ctx in
  modify (fun s -> 
    { s with rev_stem = 
      let path_item =
        Path_item.Tag { tag ; alternatives ; key =
          Stepkey step ; logged_inputs = s.logged_inputs }
      in
      Rev_stem.cons path_item 
        s.rev_stem ~if_exceeds:(Target.priority target)
    }
  )

(**
  [push_and_log_tag tag] pushes the [tag] to the path stem without alternatives
    and logs [tag] as the input. Both actions are with respect to the current
    time.
*)
let push_and_log_tag (tag : Tag.t) : (unit, 'env) m =
  let* step = step in
  let* { target ; _ } = read_ctx in
  modify (fun s -> 
    { s with rev_stem = begin
      let path_item =
        Path_item.Tag { tag ; alternatives = [] ; key =
          Stepkey step ; logged_inputs = s.logged_inputs }
      in
      Rev_stem.cons path_item s.rev_stem
        ~if_exceeds:(Target.priority target)
    end
    ; logged_inputs = Input_env.add KTag (Stepkey step) tag s.logged_inputs
    }
  )

(**
  [push_formula_to_path ?allow_flip formula] pushes the formula to the path stem
    as a true formula, such that any evaluation following the same path again must
    satifisfy the formula. By default, a target will be made from the negation
    of the formula, unless [allow_flip] is false.
*)
let push_formula_to_path ?(allow_flip : bool = true)
  (formula : (bool, Stepkey.t) Smt.Formula.t) : (unit, 'env) m =
  if Smt.Formula.is_const formula
  then return ()
  else
    let* { target ; _ } = read_ctx in
    modify (fun s -> 
      { s with rev_stem =
        let path_item =
          if allow_flip then
            Path_item.Formula { cond = formula ; logged_inputs = s.logged_inputs }
          else
            Nonflipping formula
        in
        Rev_stem.cons path_item s.rev_stem
          ~if_exceeds:(Target.priority target)
      }
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
  let log_input input = 
    modify (fun s -> { s with logged_inputs =
      Input_env.add kind (Stepkey step) input s.logged_inputs })
  in
  match Input_env.find kind (Stepkey step) input_env with
  | Some i -> let* () = log_input i in return i
  | None -> let* () = log_input default in return default

(**
  [target_to_here] is a target representing the path to the current
    program point. It is trivial to solve because its solution is
    the logged input environment.
*)
let target_to_here : 'env. (Target.t, 'env) m =
  { run = fun ~reject:_ ~accept state step _ { target ; _ } ->
    accept (
      Target.make Formula.trivial
        (Formula.BSet.union target.all_formulas (Path.formulas state.rev_stem.rev_stem))
        state.logged_inputs
        ~path_priority:state.rev_stem.total_priority
    ) state step
  }

(**
  [fork forked_m] runs [forked_m] with the current state, environment, and
    step count. If [forked_m] is a failure case, then the result is a failure.
    Otherwise, the original state is restored, and the fork is logged as a
    run.
    Calls [Lwt_direct.yield] because this is a good moment to check for time out.
    Therefore, this function must be run inside an [Lwt_direct.spawn], which is
    not guaranteed by the type system.
*)
let fork (forked_m : (Eval_result.t, 'env) u) : (unit, 'env) m =
  let* target = target_to_here in
  let* s = get in
  let* ctx = read_ctx in
  assert (
    let n = s.rev_stem.total_priority in
    let n' = Target.priority ctx.target in
    Path_priority.geq n n'
  );
  fork forked_m { target ; det_context = ctx.det_context }
    ~setup_state:(fun state ->
      (* keeps all the logged runs *)
      { state with rev_stem = Rev_stem.discard_stem state.rev_stem }
    )
    ~restore_state:(fun e ~og ~forked_state ->
      { og with runs =
        let forked_run =
          { Logged_run.rev_stem = forked_state.rev_stem 
          ; target 
          ; answer = Eval_result.to_answer e }
        in
        (* Note that the forked state runs include the original runs (see setup_state) *)
        forked_run :: forked_state.runs (* ... hence, don't copy the og runs *)
      }
    )
    (fun res ->
      if Eval_result.is_signal_to_stop res
      then escape res (* propagate up the failure *)
      else (Lwt_direct.yield (); return ()))

type 'a suspension_kind =
  | SLazy : Val.vlazy suspension_kind
  | SAlist : Val.alist suspension_kind

let read_cell : type a env. a suspension_kind -> a Suspension.t -> (a, env) m =
  fun kind susp ->
    let* s = get in
    let map : a Suspension.Map.t =
      match kind with
      | SLazy -> s.lazies
      | SAlist -> s.detfun_alists
    in
    return (Suspension.Map.find_exn susp map)

let set_cell : type a env. a suspension_kind -> a Suspension.t -> a -> (unit, env) m =
  fun kind susp v ->
    modify (fun s ->
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
let disallow_inputs (x : ('a, 'env) m) : ('a, 'env) m =
  local_ctx (fun ctx -> { ctx with det_context = Disallowed }) x

(**
  [allow_inputs x] runs [x] such that any [assert_inputs_allowed]
    is NOT a failure.
*)
let allow_inputs (x : ('a, 'env) m) : ('a, 'env) m =
  local_ctx (fun ctx -> { ctx with det_context = Allowed }) x

let run' (x : ('a, Val.Env.t) m) (target : Target.t) (s : State.t) (e : Val.Env.t) : Eval_result.t * State.t =
  match run x s e { target ; det_context = Allowed } with
  | Ok _, state -> Done, state
  | Error e, state -> e, state

(**
  [run x target] runs [x] with [target] as the context, beginning with
    empty state and environment.
*)
let run (x : ('a, Val.Env.t) m) (target : Target.t) : Eval_result.t * State.t =
  run' x target State.empty Env.empty

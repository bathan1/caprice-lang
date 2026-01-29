
open Grammar

let make_targets ~(max_tree_depth : int) (target : Target.t)
  (stem : Path.t) : Target.t list * bool =
  let rec make acc_targets acc_prio acc_formulas = function
    | [] -> acc_targets, false (* done, and did not prune *)
    | (p_item : Path_item.t) :: tl ->
      if Path_priority.to_int acc_prio > max_tree_depth then
        acc_targets, true (* done because pruned *)
      else
      let path_priority =
        Path_priority.plus_int acc_prio (Path_item.to_priority p_item)
      in
      match p_item with
      | Path_item.Nonflipping formula ->
        make acc_targets path_priority (Formula.BSet.add formula acc_formulas) tl
      | Formula { cond ; logged_inputs } ->
        let new_target =
          Target.make (Formula.not_ cond) acc_formulas logged_inputs
            ~path_priority
        in
        make (new_target :: acc_targets) path_priority (Formula.BSet.add cond acc_formulas) tl
      | Tag { tag = _ ; alternatives ; key ; logged_inputs } ->
        let new_targets =
          List.map (fun alt_tag ->
            Target.make 
              Formula.trivial
              acc_formulas
              (Input_env.add KTag key alt_tag logged_inputs)
              ~path_priority:(Path_priority.plus_int acc_prio (Tag.priority alt_tag))
          ) alternatives
        in
        make (new_targets @ acc_targets) path_priority acc_formulas tl
  in
  make [] (Target.priority target) target.all_formulas stem

let collect_logged_runs ~(max_tree_depth : int) (runs : Logged_run.t list) : 
  [ `Quit of Answer.t | `Cont of Target.t list * Answer.t ] =
  let rec collect acc_targets acc_answer = function
    | [] -> `Cont (acc_targets, acc_answer)
    | (run : Logged_run.t) :: _ when Answer.is_signal_to_stop run.answer ->
      `Quit run.answer
    | run :: tl ->
      let new_targets, is_pruned =
        make_targets run.target (Rev_stem.to_forward_path run.rev_stem) ~max_tree_depth
      in
      let targets = new_targets @ acc_targets in
      let run_answer = if is_pruned then Answer.prune run.answer else run.answer in
      let answer = Answer.min acc_answer run_answer in
      collect targets answer tl
  in
  collect [] Exhausted runs

let c = Utils.Counter.create ()

let make_int_feeder ~(run_num : int) : unit -> int =
  if run_num = 0 then
    fun () -> 0
  else
    fun () -> Random.int_in_range ~min:(-10) ~max:10

let make_bool_feeder ~(run_num : int) : unit -> bool =
  if run_num = 0 then
    fun () -> false
  else
    Random.bool

(* Does not do its own timeout, even though timeout is passed in with options *)
let loop ~(options : Options.t) (solve : Stepkey.t Smt.Formula.solver) 
  (pgm : Lang.Ast.program) (tq : Target_queue.t) : Answer.t Lwt.t =
  let open Lwt.Let_syntax.Let_syntax in
  let open Lwt.Syntax in
  let eval =
    Eval.eval pgm ~max_step:options.max_step ~do_splay:options.do_splay
      ~do_wrap:options.do_wrap
  in
  let rec loop tq =
    let* () = Lwt.pause () in
    match Target_queue.pop tq with
    | Some (target, tq) ->
      begin match solve target.target_formula with
      | Sat model -> loop_on_model target tq model
      | Unknown -> 
        let* a = loop tq in
        return @@ Answer.min Answer.Unknown a
      | Unsat -> loop tq
      end
    | None -> return Answer.Exhausted

  and loop_on_model target tq model =
    let run_num = Utils.Counter.next c in
    let ienv = Input_env.extend target.i_env (Input_env.of_model model) in
    let runs =
      eval ienv target
        ~default_int:(make_int_feeder ~run_num)
        ~default_bool:(make_bool_feeder ~run_num)
    in
    match collect_logged_runs runs ~max_tree_depth:options.max_tree_depth with
    | `Quit answer -> return answer
    | `Cont (targets, answer) ->
      let* a = loop (Target_queue.push_list tq targets) in
      return @@ Answer.min a answer
  in
  loop tq

module Default_Z3 = Overlays.Typed_z3.Default
module Default_solver = Smt.Formula.Make_solver' (Default_Z3)

let begin_ceval ?(print_outcome : bool = true) ~(options : Options.t)
  (pgm : Lang.Ast.program) : Answer.t =
  let time_sec = Utils.Time.convert_span options.global_timeout ~to_:Mtime.Span.s in
  let go () =
    try
      Lwt_main.run (Lwt_unix.with_timeout time_sec @@ fun () ->
        loop Default_solver.solve pgm Target_queue.initial ~options
      )
    with
    | Lwt_unix.Timeout -> Answer.Timeout options.global_timeout
  in
  Utils.Counter.reset c;
  if options.is_random then Random.self_init () else Random.init 999;
  let span, answer = Utils.Time.time go () in
  if print_outcome then
  Format.printf "Finished type checking in %0.3f ms and %d runs:\n    %s\n"
    (Utils.Time.span_to_ms span) (Utils.Counter.get c) (Answer.to_string answer);
  answer

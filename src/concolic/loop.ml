
open Grammar

let make_targets ~(max_tree_depth : int) (target : Target.t)
  (stem : Path.t) : Target.t list * bool =
  let rec make acc_prio acc_formulas = function
    | [] -> [], false (* done and did not prune *)
    | _ when Path_priority.to_int acc_prio > max_tree_depth -> [], true (* prune *)
    | p_item :: tl ->
      let path_priority =
        Path_priority.plus_int acc_prio (Path_item.to_priority p_item)
      in
      match p_item with
      | Nonflipping formula ->
        make path_priority (Formula.BSet.add formula acc_formulas) tl
      | Formula { cond ; logged_inputs } ->
        let new_target =
          Target.make (Formula.not_ cond) acc_formulas logged_inputs
            ~path_priority
        in
        let ret_targets, is_pruned = make path_priority (Formula.BSet.add cond acc_formulas) tl in
        new_target :: ret_targets, is_pruned
      | Tag { tag = _ ; alternatives ; key ; logged_inputs } ->
        let new_targets =
          List.map (fun alt_tag ->
            assert (Tag.priority alt_tag = Path_item.to_priority p_item);
            Target.make 
              Formula.trivial
              acc_formulas
              (Input_env.add KTag key alt_tag logged_inputs)
              ~path_priority
          ) alternatives
        in
        let ret_targets, is_pruned = make path_priority acc_formulas tl in
        List.rev_append new_targets ret_targets, is_pruned
  in
  make (Target.priority target) target.all_formulas stem

let collect_logged_runs ~(max_tree_depth : int) (runs : Logged_run.t list) : 
  [ `Quit of Answer.t | `Cont of Target.t list * Answer.t ] =
  let rec collect acc_targets acc_answer = function
    | [] -> `Cont (acc_targets, acc_answer)
    | run :: _ when Answer.is_error run.Logged_run.answer ->
      `Quit run.answer (* an error is the goal, and we found it! *)
    | run :: tl ->
      let new_targets, is_pruned =
        make_targets run.target (Rev_stem.to_forward_path run.rev_stem) ~max_tree_depth
      in
      let targets = List.rev_append new_targets acc_targets in
      let run_answer = if is_pruned then Answer.prune run.answer else run.answer in
      let answer = Answer.min acc_answer run_answer in
      collect targets answer tl
  in
  collect [] Exhausted runs

module Default_Z3 = Overlays.Typed_z3.Default
module Default_solver = Smt.Formula.Make_solver' (Default_Z3)

module Make (Y : sig val yield : unit -> unit end) = struct
  let begin_loop ~(options : Options.t) (pgm : Lang.Ast.program) : Answer.t * int =
    let run_count = Utils.Counter.create () in

    (* Run the program concolically in a loop *)
    let run do_splay =
      let eval =
        Eval.eval pgm ~max_step:options.max_step ~do_splay
          ~do_wrap:options.do_wrap
      in
      let rec loop tq =
        let () = Utils.Time.yield_to_timer () in
        let () = Y.yield () in
        match Target_queue.pop tq with
        | Some (target, tq) ->
          begin match Default_solver.solve target.target_formula with
          | Sat model -> loop_on_model target tq model
          | Unknown -> let a = loop tq in Answer.min Answer.Unknown a
          | Unsat -> loop tq
          end
        | None -> Answer.Exhausted

      and loop_on_model target tq model =
        let run_num = Utils.Counter.next run_count in
        let ienv = Input_env.extend target.i_env (Input_env.of_model model) in
        let runs =
          if run_num = 0 then
            eval ienv target
              ~default_int:(fun () -> 0)
              ~default_bool:(fun () -> false)
          else
            eval ienv target
              ~default_int:(fun () -> Random.int_in_range ~min:(-10) ~max:10)
              ~default_bool:Random.bool
        in
        match collect_logged_runs runs ~max_tree_depth:options.max_tree_depth with
        | `Quit answer ->
          answer
        | `Cont (targets, answer) ->
          let a = loop (Target_queue.push_list tq targets) in
          Answer.min a answer
      in
      loop Target_queue.initial
    in

    let run_splaying_modes () =
      match options.splay with
      | Splay_only -> run true
      | Never_splay -> run false
      | Fallback ->
        (* try to splay first *)
        let answer = run true in
        if Answer.is_error answer then
          (* The loop stopped due to error, so try without splaying in
            case the error was due to incompleteness. *)
          let () = Utils.Counter.reset run_count in
          run false
        else
          answer
    in

    let answer =
      match Utils.Time.with_timeout options.global_timeout run_splaying_modes () with
      | Ok a -> a
      | Error t -> Answer.Timeout t
    in
    answer, Utils.Counter.get run_count

  let begin_ceval ?(print_outcome : bool = true) ~(options : Options.t)
    (pgm : Lang.Ast.program) : Answer.t =
    if options.is_random then Random.self_init () else Random.init 999;
    let span, (answer, run_count) = Utils.Time.time (begin_loop ~options) pgm in 
    if print_outcome then
      Format.printf "Finished type checking in %0.3f ms and %d runs:\n    %s\n"
        (Utils.Time.span_to_ms span) run_count (Answer.to_string answer);
    answer
end

(* default behavior yields no effect, and no performance overhead! *)
include Make (struct let yield () = () end)

(* Proof of concept round robin with effects *)

type _ eff += Pause : unit eff

module Pause_effect = struct
  let yield () = 
    Effect.perform Pause
end

module M = Make (Pause_effect)

(* Example ceval one program *)
(* This is observably equivalent to begin_ceval in the default behavior above *)
let ceval_with_pause ~options pgm =
  try
    M.begin_ceval ~options pgm
  with
  | effect Pause, k ->
    Effect.Deep.continue k ()

type r =
  | Done of Answer.t
  | Cont of (unit, r) Effect.Deep.continuation

type work_item = { id : int ; task : unit -> r }

let round_robin ~spans (fs : work_item list) : unit =
  let run_q = Queue.of_seq (List.to_seq fs) in
  let enqueue id k =
    let task () = Effect.Deep.continue k () in
    Queue.push { id ; task } run_q
  in
  let rec dequeue () =
    match Queue.take_opt run_q with
    | None -> ()
    | Some { id ; task } ->
      let r =
        try task () with
        | effect Pause, k ->
          Cont k
      in
      match r with
      | Done a -> 
        Lsp.Print.print_answer ~spans id a;
        dequeue ()
      | Cont k -> enqueue id k; dequeue ()
  in
  dequeue ()

let ceval_many ~options ~spans pgms =
  round_robin ~spans (
    List.map (fun (id, pgm) ->
      { id ; task = fun () -> Done (M.begin_ceval ~print_outcome:false ~options pgm) }
    ) pgms
  )

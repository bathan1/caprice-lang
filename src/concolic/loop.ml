
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
    (* let open Lwt.Syntax in *)
    (* hack to shadow Lwt so the following code doesn't really change *)
    let (let+) x f = f x in
    let (let*) x f = f x in
    let module Lwt = struct
      let return a = a
      let pause () = ()
    end
    in

    let run_count = Utils.Counter.create () in

    (* Run the program concolically in a loop *)
    let run do_splay =
      let eval =
        Eval.eval pgm ~max_step:options.max_step ~do_splay
          ~do_wrap:options.do_wrap
      in
      let rec loop tq =
        let* () = Lwt.pause () in
        let () = Y.yield () in
        match Target_queue.pop tq with
        | Some (target, tq) ->
          begin match Default_solver.solve target.target_formula with
          | Sat model -> loop_on_model target tq model
          | Unknown -> let+ a = loop tq in Answer.min Answer.Unknown a
          | Unsat -> loop tq
          end
        | None -> Lwt.return Answer.Exhausted

      and loop_on_model target tq model =
        let run_num = Utils.Counter.next run_count in
        let ienv = Input_env.extend target.i_env (Input_env.of_model model) in
        let* runs =
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
          Lwt.return answer
        | `Cont (targets, answer) ->
          let+ a = loop (Target_queue.push_list tq targets) in
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
        let* answer = run true in
        if Answer.is_error answer then
          (* The loop stopped due to error, so try without splaying in
            case the error was due to incompleteness. *)
          let () = Utils.Counter.reset run_count in
          run false
        else
          Lwt.return answer
    in

    (* let time_sec = Utils.Time.convert_span options.global_timeout ~to_:Mtime.Span.s in
    let answer =
      try
        Lwt_main.run (Lwt_unix.with_timeout time_sec run_splaying_modes)
      with
      | Lwt_unix.Timeout -> Answer.Timeout options.global_timeout
    in
    answer, Utils.Counter.get run_count *)
    (* don't do any timeout *)
    let answer = run_splaying_modes () in
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
(* This is identical to begin_ceval in the default behavior above *)
let ceval_with_pause ~options pgm =
  try
    M.begin_ceval ~print_outcome:false ~options pgm
  with
  | effect Pause, k ->
    Effect.Deep.continue k ()

type r =
  | Done of int * Answer.t
  | Cont of int * (unit, r) Effect.Deep.continuation

(* Now extend to work on many programs *)
let ceval_many ~options ~spans pgms =
  (* fencepost by beginning the evaluations *)
  let worklist =
    List.map (fun (stmt_idx, pgm) ->
      try
        Done (stmt_idx, fst (M.begin_loop ~options pgm))
      with
      | effect Pause, k ->
        Cont (stmt_idx, k)
    ) pgms
  in
  (* now go around until the work list is empty *)
  let rec round_robin = function
    | [] -> ()
    | Done (i, answer) :: tl ->
      Lsp.Print.print_answer ~spans i answer;
      round_robin tl
    | Cont (i, k) :: tl ->
      (* this program is not done. continue it once and catch the effect *)
      let r =
        try
          Effect.Deep.continue k ()
        with
        | effect Pause, k ->
          Cont (i, k)
      in
      (* put the continuation on the back of the work list and keep going *)
      round_robin (tl @ [ r ])
  in
  round_robin worklist

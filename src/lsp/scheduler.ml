type _ eff += Pause : unit eff

module Pause_effect = struct
  let yield () =
    Effect.perform Pause
end

type strategy = Stripped_splay | Non_splay

type fallback_spawn = {
  refinement_positions : Lang.Ast.pos_span list ;
  stripped_splay_task : unit -> r ;
  non_splay_task : unit -> r ;
}

and r =
  | Done of Grammar.Answer.t
  | Cont of (unit, r) Effect.Deep.continuation
  | Spawn_fallback of fallback_spawn

type role =
  | Initial_splay
  | Fallback of { group_id : int ; strategy : strategy }

type work_item = {
  role : role ;
  span : Lang.Ast.pos_span ;
  task : unit -> r ;
}

type group_state = {
  span : Lang.Ast.pos_span ;
  refinement_positions : Lang.Ast.pos_span list ;
  stripped : Grammar.Answer.t option ;
  non_splay : Grammar.Answer.t option ;
  cancelled : bool ;
}

module Gid = Map.Make (Int)

let decide (gs : group_state) (strategy : strategy) (answer : Grammar.Answer.t) : group_state =
  let gs =
    match strategy with
    | Stripped_splay -> { gs with stripped = Some answer }
    | Non_splay      -> { gs with non_splay = Some answer }
  in
  match strategy, answer with
  | Non_splay, Grammar.Answer.Found_error _ ->
    Print.print_answer gs.span answer ;
    { gs with cancelled = true }
  | _ ->
    begin match gs.stripped, gs.non_splay with
    | Some stripped, Some non_splay ->
      begin match stripped, non_splay with
      | Grammar.Answer.Found_error _, _
      | _, Grammar.Answer.Found_error _ -> ()
      | _, _ -> List.iter Print.print_refinement_warning gs.refinement_positions
      end ;
      Print.print_answer gs.span non_splay ;
      { gs with cancelled = true }
    | _ -> gs
    end

let round_robin (fs : work_item list) : unit =
  let run_q = Queue.of_seq (List.to_seq fs) in
  let enqueue_cont wi k =
    let task () = Effect.Deep.continue k () in
    Queue.push { wi with task } run_q
  in
  let enqueue_fallback gid (spawn : fallback_spawn) (wi : work_item) =
    let mk strategy task =
      { role = Fallback { group_id = gid ; strategy } ; span = wi.span ; task }
    in
    Queue.push (mk Stripped_splay spawn.stripped_splay_task) run_q ;
    Queue.push (mk Non_splay      spawn.non_splay_task)      run_q
  in
  let on_done wi answer groups =
    match wi.role with
    | Initial_splay ->
      Print.print_answer wi.span answer ;
      groups
    | Fallback { group_id ; strategy } ->
      let gs = Gid.find group_id groups in
      Gid.add group_id (decide gs strategy answer) groups
  in
  let on_spawn (wi : work_item) (spawn : fallback_spawn) next_gid groups =
    let gs = {
      span = wi.span ;
      refinement_positions = spawn.refinement_positions ;
      stripped = None ;
      non_splay = None ;
      cancelled = false ;
    } in
    enqueue_fallback next_gid spawn wi ;
    next_gid + 1, Gid.add next_gid gs groups
  in
  let rec dequeue next_gid groups =
    match Queue.take_opt run_q with
    | None -> ()
    | Some wi ->
      begin match wi.role with
      | Fallback { group_id ; strategy = _ } when (Gid.find group_id groups).cancelled ->
        dequeue next_gid groups
      | _ ->
        let r =
          try wi.task () with
          | effect Pause, k -> Cont k
        in
        begin match r with
        | Done answer ->
          dequeue next_gid (on_done wi answer groups)
        | Cont k ->
          enqueue_cont wi k ;
          dequeue next_gid groups
        | Spawn_fallback spawn ->
          let next_gid, groups = on_spawn wi spawn next_gid groups in
          dequeue next_gid groups
        end
      end
  in
  dequeue 0 Gid.empty

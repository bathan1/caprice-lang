type _ eff += Pause : unit eff

module Pause_effect = struct
  let yield () = Effect.perform Pause
end

type r =
  | Done
  | Cont of (unit, r) Effect.Deep.continuation
  | Spawn of work_item list
  | Cancel_peers of Lang.Ast.pos_span

and work_item =
  { span : Lang.Ast.pos_span
  ; task : unit -> r
  }

let round_robin (fs : work_item list) : unit =
  let run_q = Queue.of_seq (List.to_seq fs) in
  let cancelled : (Lang.Ast.pos_span, unit) Hashtbl.t = Hashtbl.create 16 in
  let is_cancelled span = Hashtbl.mem cancelled span in
  let enqueue span k =
    let task () = Effect.Deep.continue k () in
    Queue.push { span ; task } run_q
  in
  let rec dequeue () =
    match Queue.take_opt run_q with
    | None -> ()
    | Some { span ; task = _ } when is_cancelled span -> dequeue ()
    | Some { span ; task } ->
      let r =
        try task () with
        | effect Pause, k -> Cont k
      in
      begin match r with
      | Done -> dequeue ()
      | Cont k -> enqueue span k; dequeue ()
      | Spawn children ->
        List.iter (fun c -> Queue.push c run_q) children;
        dequeue ()
      | Cancel_peers s ->
        Hashtbl.replace cancelled s ();
        dequeue ()
      end
  in
  dequeue ()

open Smt
open Overlays

open Unix

let sql_escape (s : string) =
  s
  |> String.split_on_char '\''
  |> String.concat "''"

let time_us_float f =
  let t1 = gettimeofday () in
  let _ = f () in
  let t2 = gettimeofday () in
  (t2 -. t1) *. 1_000_000.0

let main_solve_with_metadata expr = Solve.main_solve_with_metadata (module Typed_z3.Default) expr

let benchmark num_trials =
  let solve_z3_only =
    Solve.direct_solve (module Typed_z3.Default)
  in

  let fs =
    Boolean.from_stdin ()
  in

  Printf.printf
    "CREATE TABLE IF NOT EXISTS benchmarks (\n\
    \  trial_num INTEGER NOT NULL,\n\
    \  formula_id INTEGER NOT NULL,\n\
    \  formula TEXT NOT NULL,\n\
    \  was_backend_used TEXT NOT NULL,\n\
    \  time_us_blue3 FLOAT NOT NULL,\n\
    \  time_us_z3 FLOAT NOT NULL\n\
     );\n\n";

  let rec aux trial_num =
    if trial_num = num_trials then
      ()
    else begin
      fs
      |> List.iteri (fun formula_id ftext ->
          let formula_sql =
            sql_escape ftext
          in

          let f =
            Boolean.parse ftext
          in

          let metadata_ref =
            ref { Solve.was_backend_used = false }
          in

          let time_us_blue3 =
            time_us_float (fun () ->
                let _solution, ~metadata =
                  main_solve_with_metadata f
                in
                metadata_ref := metadata)
          in

          let time_us_z3 =
            time_us_float (fun () ->
                let f =
                  Boolean.parse ftext
                in
                ignore (solve_z3_only f))
          in

          let was_backend_used =
            !metadata_ref.Solve.was_backend_used
          in

          Printf.printf
            "INSERT INTO benchmarks (trial_num, formula_id, formula, was_backend_used,\
             time_us_blue3, time_us_z3) VALUES (%d, %d, '%s', '%s', %.6f, %.6f);\n"
            trial_num
            formula_id
            formula_sql
            (Bool.to_string was_backend_used)
            time_us_blue3
            time_us_z3);

      aux (trial_num + 1)
    end
  in

  aux 0

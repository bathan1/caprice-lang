open Smt
open Overlays
open Utils

let sql_escape (s : string) =
  s
  |> String.split_on_char '\''
  |> String.concat "''"

let main_solve_with_metadata expr =
  Solve.main_solve_with_metadata (module Typed_z3.Default) expr

let find_avg label results =
  match List.assoc_opt label results with
  | Some time_us -> time_us
  | None -> failwith ("missing benchmark result: " ^ label)

let benchmark num_trials =
  let solve_z3_only =
    Solve.direct_solve (module Typed_z3.Default)
  in

  let fs =
    Boolean.from_stdin ()
  in

  Printf.eprintf
    "CREATE TABLE IF NOT EXISTS benchmarks (\n\
    \  formula_id INTEGER NOT NULL,\n\
    \  formula TEXT NOT NULL,\n\
    \  was_backend_used TEXT NOT NULL,\n\
    \  time_us_blue3 FLOAT NOT NULL,\n\
    \  time_us_z3 FLOAT NOT NULL\n\
     );\n\n";

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

    let results =
      Benchmarker.bench_many_avg
        ~trials:num_trials
        [ ( "blue3"
          , (fun () ->
            let _solution, ~metadata =
              main_solve_with_metadata f
            in
            metadata_ref := metadata)
          , ()
        )

          ; ( "z3"
            , (fun () ->
              let f =
                Boolean.parse ftext
              in
              ignore (solve_z3_only f))
            , ()
          )
        ]
    in

    let time_us_blue3 =
      find_avg "blue3" results
    in

    let time_us_z3 =
      find_avg "z3" results
    in

    let was_backend_used =
      !metadata_ref.Solve.was_backend_used
    in

    Printf.eprintf
      "INSERT INTO benchmarks (formula_id, formula, was_backend_used,\
         time_us_blue3, time_us_z3) VALUES (%d, '%s', '%s', %.6f, %.6f);\n"
      formula_id
      formula_sql
      (Bool.to_string was_backend_used)
      time_us_blue3
      time_us_z3)

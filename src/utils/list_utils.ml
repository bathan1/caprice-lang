let fold_left_until f finish init ls =
  let rec go acc = function
    | [] -> finish acc
    | hd :: tl ->
      match f acc hd with
      | `Stop x -> x
      | `Continue a -> go a tl
  in
  go init ls

let rec find_pair (f : 'a -> 'b -> bool) (xs : 'a list) (ys : 'b list) : ('a * 'b) option =
  match xs with
  | [] -> None
  | x :: xs' ->
    match List.find_opt (f x) ys with
    | None -> find_pair f xs' ys
    | Some y -> Some (x, y)

let rec remove1 x ls =
  match ls with
  | [] -> []
  | a :: ls' -> if (x = a) then ls' else a :: (remove1 x ls')

let fold_lefti f init ls =
  let rec fold i acc = function
    | [] -> acc
    | hd :: tl ->
        fold (i + 1) (f i acc hd) tl
  in
  fold 0 init ls

let join ~sep f ls =
  let n = List.length ls in
  fold_lefti (fun i acc el ->
    acc ^ f el ^ (if i < n - 1 then sep else "")
  ) "" ls

(** [combination2 ls] returns the [(n * (n - 1)) / 2] 2-combination tuple list of each element in LS

    {[
      open Utils

      let () =
        let elements = List.init 5 Fun.id in
        let two_combs = List_utils.combination2 elements in
        List.iter (fun (a, b) -> Printf.printf "(%d, %d), " a b) two_combs
    ]}
    *)
let combination2 (ls : 'a list) =
  let rec to_pairs acc = function
    | [] -> List.rev acc
    | x :: rest ->
      let pairs = List.map (fun y -> (x, y)) rest in
      to_pairs (List.rev_append pairs acc) rest
  in
  to_pairs [] ls

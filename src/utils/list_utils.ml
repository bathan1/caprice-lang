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

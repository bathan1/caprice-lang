let fold_left_until f finish init ls =
  let rec go acc = function
    | [] -> finish acc
    | hd :: tl ->
      match f acc hd with
      | `Stop x -> x
      | `Continue a -> go a tl
  in
  go init ls

let rec find_pair_opt (f : 'a -> 'b -> bool) (xs : 'a list) (ys : 'b list) : ('a * 'b) option =
  match xs with
  | [] -> None
  | x :: xs' ->
    match List.find_opt (f x) ys with
    | None -> find_pair_opt f xs' ys
    | Some y -> Some (x, y)

let find_pair (f : 'a -> 'b -> bool) (xs : 'a list) (ys : 'b list) : ('a * 'b) =
  match find_pair_opt f xs ys with
  | None -> failwith "\n[find_pair]: No x and y from XS and YS satisfied F(X, Y)"
  | Some pair -> pair

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


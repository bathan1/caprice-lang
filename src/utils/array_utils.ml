let fold_left_until
  (f : 'acc -> 'a -> [ `Continue of 'acc | `Stop of 'acc ])
  (init : 'acc)
  (arr : 'a array)
  : 'acc =
  let rec loop (i : int) (acc : 'acc) =
    let el = arr.(i) in
    match f acc el with
    | `Continue acc' -> loop (i + 1) acc'
    | `Stop acc' -> acc'
  in
  loop 0 init 

let fold_lefti_until
  (f : int -> 'acc -> 'a -> [ `Continue of 'acc | `Stop of 'acc ])
  (init : 'acc)
  (arr : 'a array)
  : 'acc =
  let rec loop i acc =
    if i >= Array.length arr then acc
    else
      match f i acc arr.(i) with
      | `Continue acc' -> loop (i + 1) acc'
      | `Stop acc' -> acc'
  in
  loop 0 init

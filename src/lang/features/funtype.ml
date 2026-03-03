
type mode =
  | Det
  | Nondet

let equal_mode a b =
  match a, b with
  | Det, Det
  | Nondet, Nondet -> true
  | _ -> false

type ('dom, 'cod) t = { domain : 'dom ; codomain : 'cod ; mode : mode }

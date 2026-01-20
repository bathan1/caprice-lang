
type det
type nondet

type mode =
  | Det
  | Nondet
  [@@deriving eq, ord]

type ('dom, 'cod) t = { domain : 'dom ; codomain : 'cod ; mode : mode }
  [@@deriving eq, ord]

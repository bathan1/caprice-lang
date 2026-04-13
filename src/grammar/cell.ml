
open Lang

type 'a kind =
  | SLazy : Val.vlazy kind
  | STable : Val.table kind
  | SComp_mu : Val.comp_mu kind
  | SWitness : Val.witness list kind

type 'a t = 'a kind * 'a Suspension.t

module Map = struct
  type t =
    { lazies : Val.vlazy Suspension.Map.t
    ; tables : Val.table Suspension.Map.t
    ; comps : Val.comp_mu Suspension.Map.t
    ; witnesses : Val.witness list Suspension.Map.t
    }

  let empty =
    { lazies = Suspension.Map.empty
    ; tables = Suspension.Map.empty
    ; comps = Suspension.Map.empty
    ; witnesses = Suspension.Map.empty
    }
end

let get (type a) ((kind, susp) : a t) (map : Map.t) : a =
  let map : a Suspension.Map.t =
    match kind with
    | SLazy -> map.lazies
    | STable -> map.tables
    | SComp_mu -> map.comps
    | SWitness -> map.witnesses
  in
  Suspension.Map.find_exn susp map

let set (type a) ((kind, susp) : a t) (a : a) (map : Map.t) : Map.t =
  match kind with
  | SLazy -> { map with lazies = Suspension.Map.add susp a map.lazies }
  | STable -> { map with tables = Suspension.Map.add susp a map.tables }
  | SComp_mu -> { map with comps = Suspension.Map.add susp a map.comps }
  | SWitness -> { map with witnesses = Suspension.Map.add susp a map.witnesses }

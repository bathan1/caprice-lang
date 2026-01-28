
type 'a t = 'a Labels.Record.Map.t
  [@@deriving eq, ord]

let empty = Labels.Record.Map.empty

let fold (f : Labels.Record.t -> 'a -> 'acc -> 'acc) (acc : 'acc) (x : 'a t) : 'acc =
  Labels.Record.Map.fold f x acc

let label_set (x : 'a t) : Labels.Record.Set.t =
  Labels.Record.Map.domain x

module Parsing = struct
  let of_list pair_ls =
    let add_entry acc (k, v) = 
      Labels.Record.Map.update k (function
        | Some _ -> raise @@ Invalid_argument "Duplicate record entry while parsing."
        | None -> Some v
      ) acc
    in
    List.fold_left add_entry Labels.Record.Map.empty pair_ls
end

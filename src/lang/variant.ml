
module Label = struct
  module T = struct
    type t = VariantLabel of Ident.t [@@unboxed]

    let compare (VariantLabel a) (VariantLabel b) =
      Ident.compare a b

    let equal (VariantLabel a) (VariantLabel b) =
      Ident.equal a b
  end

  include T

  let to_ident (VariantLabel id) = id
  let of_ident id = VariantLabel id

  let to_string (VariantLabel id) = "`" ^ Ident.to_string id

  include Utils.Set_map.Make_W (T)
end

type 'a t = { label : Label.t ; payload : 'a }

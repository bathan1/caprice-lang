
type t = 
  | EUnit
  | EInt of int
  | EBool of bool
  | EVar of Ident.t
  | EBinop of { left : t ; binop : Binop.t ; right : t }
  | EIf of { if_ : t ; then_ : t ; else_ : t }
  | ELet of { stmt : statement ; body : t }
  | EAppl of { func : t ; arg : t }
  | EMatch of { subject : t ; patterns : (Pattern.t * t) list }
  | EProject of { record : t ; label : Labels.Record.t }
  | ERecord of t Record.t
  | ETuple of t * t
  | EEmptyList
  | EListCons of { hd : t ; tl : t }
  | EModule of statement list
  | ENot of t
  | EPick_i
  | EFunction of { param : Ident.t ; body : t }
  | EVariant of t Variant.t
  | EAssert of t
  | EAssume of t
  | EAbstractType (* evaluates to an abstract type *)
  (* Types *)
  | EType
  | ETypeInt
  | ETypeBool
  | ETypeTop
  | ETypeBottom
  | ETypeUnit
  | ETypeRecord of t Record.t
  | ETypeModule of (Labels.Record.t * t) list
  | ETypeFun of (Ident.t option * t, t) Funtype.t
  | ETypeRefine of (t, t) Refinement.t
  | ETypeMu of { var : Ident.t ; body : t }
  | ETypeList of t
  | ETypeVariant of t Variant.t list
  | ETypeSingle of t
  [@@deriving eq, ord]

and annot =
  | ANone
  | AType of { tau : t ; do_check : bool }

and statement =
  | SLet of { name : Ident.t ; annot : annot ; defn : t }
  | SLetRec of { name : Ident.t ; annot : annot ; param : Ident.t ; defn : t }
  [@@deriving eq, ord]

type program = statement list

module Tools = struct
  let id_of_stmt = function
    | SLet { name ; _ }
    | SLetRec { name ; _ } -> name

  let mk_curried_fun params body =
    List.fold_right (fun param body ->
      EFunction { param ; body }
    ) params body

  let default_fun_mode = Funtype.Nondet

  let mk_curried_funtype params codomain =
    List.fold_right (fun (_, domain) codomain ->
      ETypeFun { domain ; codomain ; mode = default_fun_mode }
    ) params codomain

  let extract_param_names params =
    List.map fst params
  
  let disable_annot_check (annot : annot) : annot =
    match annot with
    | ANone -> ANone
    | AType r -> AType { r with do_check = false }
  
  let disable_stmt_check (stmt : statement) : statement =
    match stmt with
    | SLet r -> SLet { r with annot = disable_annot_check r.annot }
    | SLetRec r -> SLetRec { r with annot = disable_annot_check r.annot }
  
  let filter_check_stmt (stmts : statement list) (target_idx : int option) : statement list =
    match target_idx with
    | None -> stmts
    | Some target_idx ->
      if (target_idx < 0 || target_idx >= List.length stmts) then
        failwith (Printf.sprintf "Target index %d is out of bounds" target_idx)
      else
        List.mapi (fun i stmt ->
          if i = target_idx then stmt
          else disable_stmt_check stmt
        ) stmts
end

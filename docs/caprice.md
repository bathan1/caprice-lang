
# Caprice language

## Overview

Caprice is a simple, semantically typed functional language with types as values. In this project, one writes Caprice programs with the intent to type check them, as the purpose of Caprice is demonstrate semantic type refutation. There is currently no way to only _run_ Caprice programs, but they are run many times during type checking, so if you want to run your program, just type check it!

The syntax of Caprice is OCaml-like, except if OCaml did not need special syntax for types and modules; types and modules are first class in Caprice.

Caprice uses semantics types. The type system is not syntactic. Only explicitly type-annotated statements are checked, and they are checked semantically: an expression $e$ has type $\tau$ if $e$ evaluates to a value with type $\tau$. This is done with concolic evaluation to enumerate the evaluations of $e$ and attempt to find a resulting value $v$ that is _not_ in $\tau$. Remember: since only explicitly typed statements are checked, all code is otherwise completely untyped. There is no type inference.

Every Caprice program is a module. Modules are statement lists, where a statement defines a binding.

Caprice's semantics are eager.

## Examples

We will walk through a series of examples to demonstrate the syntax of Caprice.

### Programs are statement lists

An extremely basic program is a single statement.

```ocaml
let x = 0
```

This program evaluates to a module containing the binding $x \mapsto 0$. This program is "type checked" by ensuring that it runs without failure. It does.

Add type annotations to get more checking.

```ocaml
let x : int = 0
```

The type checker ensures that `x` always binds to an integer.

One can use types as values and sequenced statements to write the same thing as follows.

```ocaml
let t = int
let x : t = 0
```

Note that `t` is defined with an untyped statement. One may similarly write `let t : type = int` to ensure that `t` is a type. Modularize such a program with modules as values:

```ocaml
let T : sig
  val t : type
end = struct
  let t = int
end

let x : T.t = 0
```

Notice that there is no abstraction of the type `T.t`. The mirror program in OCaml would have a type error because `T.t` is abstract. However, with semantic type checking, this program always checks because it cannot go wrong.

### Functions

Caprice supports function sugar similarly to OCaml. That is, the following two statements are the same. Both evaluate and are type checked identically.

```ocaml
let f (x : int) : int = x
let f : int -> int = fun x -> x
```

We will tend to use the first syntax in this document.

Let's next write a list map function. Remember that types are first class values, and there is no special semantics of types. `list` is a built in function on types, so the application `list int` evaluates to a type describing lists of integers. If one writes `list a`, then `a` must be bound to some value. That is, if one writes the following program, they will have unbound values `a` and `b`.

```ocaml
let rec map (f : a -> b) (ls : list a) : list b =
  match ls with
  | [] -> []
  | hd :: tl -> f hd :: map f tl
  end
```

So how does one write polymorphic functions? Caprice has dependently typed functions for that! We would first introduce `a` and `b` as parameters with type `type`.

```ocaml
let rec map (a : type) (b : type) (f : a -> b) (ls : list a) : list b = ...
```

However, since the rest of the parameters _depend_ on `a` and `b`, they must be annotated as `dependent`, or `dep` for short.

```ocaml
let rec map (dep a : type) (dep b : type) (f : a -> b) (ls : list a) : list b = ...
```

This is such a common coding pattern, that we have the following sugar for it.

```ocaml
let rec map (type a) (type b) (f : a -> b) (ls : list a) : list b = ...
```

This, too, is so common that there is even more sugar to combine the parameters.

```ocaml
let rec map (type a b) (f : a -> b) (ls : list a) : list b =
  match ls with
  | [] -> []
  | hd :: tl -> f hd :: map a b f tl
  end
(*
  As a signature:
    val map : (type a b) -> (a -> b) -> list a -> list b
  or equally
    val map : (a : type) -> (b : type) -> (a -> b) -> list a -> list b
*)
```

But notice that since types are values, and `map` takes two type arguments before the function `f`, the recursive call must pass the arguments through. This allows polymorphic recursion! The downside is that polymorphism must be explicitly typed without inference, for example to map an integer list to a boolean list, we pass `int` and `bool` as the first two arguments.

```ocaml
let _ = map int bool (fun i -> i % 2 == 0) [1;2;3]
```

### Other types

We saw above that Caprice has dependently typed functions: a function's codomain type can depend the value of its domain. Caprice has a number of other types, too, some of which we've already seen, including refinements, variants, records, modules, `type`, unit, and singleton.

Let's cover the example from the [README](../README.md), one statement at a time.

First, we define a type `pos_int` that is a refinement on integers; it is the set of all positive integers.

```ocaml
let pos_int : type = { i : int | i > 0 }
```

Next, we can make a `Collection` module with three fields, a type function `t` and two polymorphic functions `empty` and `add`.

```ocaml
let Collection : sig
  val t : type -> type
  val empty : (type a) -> t a
  val add : (type a) -> a -> t a -> t a
end = struct 
  let t = list 
  let empty _ = []
  let add _ a c = a :: c
end
```

A quick tangent: we could also choose to hoist the type parameter outside the module, as follows:

```ocaml
let Collection' : (type a) -> sig
  val t : type
  val empty : t
  val add : a -> t -> t
end = fun a -> struct 
  let t = list a
  let empty = []
  let add a c = a :: c
end
```

Then, `Collection' a` is a module describing collections over the type `a`. This just shows the power of Caprice. Move things around however you want, and we'll semantically type check it for you!

Now we can write a dependently typed recursive function to return the divisors of a positive integer.

```ocaml
let factors (dep n : pos_int) : Collection.t { m : pos_int | n % m == 0 } =
  let rec factors (dep i : pos_int) : Collection.t { k : int | k >= i && n % k == 0 } =
    if i > n then
      Collection.empty int
    else if n % i == 0 then
      Collection.add int i (factors (i + 1))
    else
      factors (i + 1)
  in
  factors 1
```

Excerise to the reader: write this using `Collection'` instead. One will notice when doing so that it is beneficial to not have abstract types because with these refinements, it is very helpful to benefit from subtyping: e.g. `{ i : int | p } <: int` for any predicate `p`, and `list` is covariant.

## An Extra IDL case
Difference logic doesn't know anything about boolean logic, including `iff` statements that have difference encodable formula terms in them. Consider the unit clause:

```
(0 <= a) = (a <= b)
```

This represents a biconditional and asserts that either `(0 <= a)` and `(a <= b)` are both true or `(0 <= a)` and `(a <= b)` are both false.

As a disjunction, you can write this as:

```txt
((0 <= a) ^ (a <= b)) v (not (0 <= a) ^ not (a <= b))
```

It turns out this can be expressed as CNF:

```txt
(not (0 <= a) v (a <= b)) ^ ((0 <= a) v not (a <= b))
```

> While we *could* rewrite the `not` cases as their truthful literals `a > 0` and `a > b`, this would generate new formula terms which is not directly encodeable as CNF because the CDCL solver would see `(p v q) ^ (r v s)` for a clause, which is *not* in CNF.

The first version of Blue3 couldn't handle this so we added specific handling for the `Equal` on two `bool` formula cases:

```diff
 | Equal ->
-  begin match x, y with
-  | Const_bool true, e -> e
-  | e, Const_bool true -> e
-  | Const_bool false, e -> not_ e
-  | e, Const_bool false -> not_ e
-  | Const_int _, Key _ -> Binop (Equal, y, x)
-  | Const_int i1, Const_int i2 -> Const_bool (i1 = i2)
-  | e1, e2 when equal e1 e2 -> true_
-  | e1, e2 -> Binop (Equal, e1, e2)
+  begin match bool_opt x, bool_opt y with
+  | Some bx, Some by -> iff bx by
+  | _ ->
+    begin match x, y with
+    | Const_int _, Key _ -> Binop (Equal, y, x)
+    | Const_int i1, Const_int i2 -> Const_bool (i1 = i2)
+    | e1, e2 when equal e1 e2 -> true_
+    | e1, e2 -> Binop (Equal, e1, e2)
+    end
   end
```

Which uses the newly introduced `iff` function:

```ocaml
  and iff (x : (bool, 'k) t) (y : (bool, 'k) t) : (bool, 'k) t =
    match x, y with
    | Const_bool true, e | e, Const_bool true -> e
    | Const_bool false, e | e, Const_bool false -> not_ e
    | e1, e2 when equal e1 e2 -> true_
    | e1, e2 -> and_ [ or_ [not_ e1; e2] ; or_ [e1; not_ e2] ]
```

`iff` propagates the literals in the first two cases that match on the `Const_bool` cases (since `true <-> e => e` and `false <-> e => not e`). Then it simplifies to `true` when `e1` and `e2` are equal.

Finally, we hit our non-trivial case:

```ocaml
| e1, e2 -> and_ [ or_ [not_ e1; e2] ; or_ [e1; not_ e2] ]
```

Which is just our CNF encoding of the biconditional. 

And you may have noticed the new `or_` constructor function. It allows you to express `Or` clauses as lists rather than
as a binary operation. It does so by nesting `Or`s over a fold on the literals:

```ocaml
and or_ (ls : (bool, 'k) t list) : (bool, 'k) t =
  match ls with
  | [] -> const_bool false
  | [x] -> x
  | x :: xs ->
    List.fold_left
      (fun acc f -> binop Or acc f)
      x
      xs
```

Those were all the changes to `Formula` that were necessary to handle this special bijection case, as I tried to keep the additions to a minimum here.
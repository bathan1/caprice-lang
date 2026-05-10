# Programming Blue3

## Motivation
Blue3 is a simple SMT solver implementation in OCaml. It was built to solve many of the simple SMT formulas that `ceval`, short for Concolic Evaluator, spits out.

Before Blue3, [Z3](https://www.microsoft.com/en-us/research/project/z3-3/) was in charge of handling the SMT solving. It still is in charge of SMT solving, but now it is used as a sort-of "fallback" for when Blue3 cannot solve the formula.

Z3 is more than capable of solving our formulas, of course, but the JHU Programming Language lab felt it was overkill for many of the cases. For instance, `ceval` might output something like:

```
(6 <= a) ^ (a < 0)
```

That formula is obviously UNSAT because `a` can't be `6` or more while also being less than `0`.

Many of the formulas `ceval` needs solved are simple / trivial like this. It's fast for Z3 to solve these formulas for sure, but our Z3 solver is the default general one. This results in Z3 performing a lot of extra processing that isn't necessary for our simple cases.

In other words, using Z3 to solve our simple formulas felt like using a bazooka to swat a fly.

Because of this along with the overhead of invoking the external Z3 C++ bindings from OCaml (since `caprice-lang` is written in OCaml), the team felt as if an in-house solver that can handle our trivial cases could improve the performance of `ceval` significantly. 

The initial solution was an informal solver that would essentially guess values for our formulas. It certainly sped up solve times for some simple cases. But it had a major design flaw which was that it had to essentially match on every formula case we deemed "simple". As it turns out, telling a computer that a formula is "simple" programatically is a somewhat nontrivial task, even if it's easy for us to see as humans.

So after diving into the SMT theory rabbit hole for a bit, I eventually landed on the Aalto University's [SMT course docs](https://users.aalto.fi/~tjunttil/2020-DP-AUT/notes-smt/index.html), which happened to have documentation on implementing a specific SMT theory solver that seemed as if it was built for our specific cases.

I am talking about the [Difference Logic](https://users.aalto.fi/~tjunttil/2020-DP-AUT/notes-smt/diff_solver.html) solver. It practically covered all of our simple cases and didn't seem too difficult to implement, so I decided to give it a go.

## Difference Logic and Bellman Ford
Difference logic is about solving **difference** formulas. Formally this means it handles terms that take on the shape:

```
(x - y) <> c
```

Where `x` and `y` are either integer *variables* or the *constant* `0`, `c` is any integer *constant*, and `<>` is a binary operator that is one of `<`, `<=`, `>`, `>=`, and `=`. Specifically, it does *not* handle the `Not equal` operator `!=`, nor does it handle formulas where the left side is the *sum* `x + y`, or any other operator other than `-` for that matter.

As it turns out, many of our "simple" cases are exactly in this difference form, including our example:

```
(6 <= a) ^ (a < 0)
```

Because we can rewrite this as:

```
(0 <= a - 6) ^ (a <= -1)
```

Then writing out out the difference with 0 explicitly...
```
(0 - a <= -6) ^ (a - 0 <= -1)
```

As humans, all this rewriting may seem like extra work because we don't need to do all this to figure out this formula is UNSAT; we just "know" from looking at the formula that it is UNSAT.

But Difference Logic allows us to encode how we "know" that this is UNSAT in a way a computer can understand. Moreover, it is able to handle the "simple" formula cases that we didn't even know were "simple", because it formalizes what type of formula it can solve.

We get the computer to tell us whether formulas like `(6 <= a) ^ (a < 0)` are satisfiable through a familiar shortest distance graph algorithm.

### Bellman Ford
The Bellman Ford algorithm finds the shortest distance paths from a particular node to all others in a directed graph.

Suppose we have a graph with the following edges:

```ocaml
let edges =
  [ ('a', '0', 3)
  ; ('0', 'a', -1)
  ; ('z', '0', 5)
  ; ('z', 'a', 5)
  ]
```

It looks something like this:

```mermaid
graph LR
  na["a"] -->|"3"| n0["0"]
  n0 -->|"-1"| na["a"]
  nz["z"] -->|"5"| n0["0"]
  nz -->|"5"| na["a"]
```

Now let's say we wanted to find the shortest distance paths from `z` to every other node. We can run bellman ford against this edge list...

```ocaml
match bellman_ford ~src:'z' edges with
| `No_negative_cycle distances ->
  print_endline "No negative cycle found.";
  List.iter (fun (node, distance) ->
    Printf.printf "dist(%c) = %d\n" node distance)
    distances

| `Negative_cycle cycle_edges ->
  print_endline "Negative cycle found:";
  List.iter (fun edge ->
    Printf.printf "- %s\n" (pp_edge edge))
    cycle_edges
```

and it will tell us:

```bash
No negative cycle found.
dist(z) = 0
dist(a) = 4
dist(0) = 5
```

The shortest distance path from `z` to `0` is just the direct edge `z -> 0` with weight `5`.

The shortest distance path from `z` to `a` is `4`, because we can go from `z` to `0` for cost `5`, then from `0` to `a` with cost `-1` to give us a shortest distance of `4`.

If we jumped from `a` back to `0` for a cost of `3`, our distance would go from `4` to `7`. So even though we can go back and forth from `a` to `0`, it will just add cost to our path to `a` to cycle back to `0`. This means there is **no negative cycle**.

Now if we changed the edge from `a -> 0` to have cost `-6`...

```ocaml
let edges =
  [ ('a', '0', -6)
  ; ('0', 'a', -1)
  ; ('z', '0', 5)
  ; ('z', 'a', 5)
  ]
```

```mermaid
graph LR
  na["a"] -->|"-6"| n0["0"]
  n0 -->|"-1"| na["a"]
  nz["z"] -->|"5"| n0["0"]
  nz -->|"5"| na["a"]
```

...then Bellman Ford will tell us:

```
Negative cycle found:
- 0 -> a (-1)
- a -> 0 (-6)
```

Because after going from `z` to `0` for cost `5`, going to `0` from `a` costs us `-1`, which leads us to total cost of `4`. And now going from `a` *back* to `0` would cost us `-6` weight for a total sum of `-2`, which is less than our previous path to `a`. We can do this as many times as we want and will end up with lower and lower weights.

So there is no shortest path from `z` to `a`, because for any shortest-path `P` we find for it, we can find a shorter path `P'` by circling over `a` and `0`. And as a consequence, we have no shortest path from `z` to *any* other node, because we can loop over the `a` and `0` edges once more for any other claimed shortest path and get a lower distance path. Thus, we have a **negative cycle**.

Bellman Ford is able to tell us all this about our graphs rather elegantly. The algorithm revolves around iterating over each edge in the edge list, where for each edge in the iteration, we run a `relax` function against it:

```ocaml
let relax_distances (num_nodes : int) (edges : int edge list) (state : loop) (i : int)
  ...
    let iter =
      List.fold_left relax_distance { paths ; is_updated } edges
    in
  ...
```

For each call to `relax_distance` against an edge `(from, to, weight)`, we just have to compare our current shortest distance to the `from` node and our current shortest to the `to` node. If our current shortest distance to `from` plus `weight` is less than our current shortest distance to the `to` node, or `dist(from) + weight < dist(to)`, then we update our shortest distance to `to` with that sum:

```ocaml
let relax_distance
  (state : loop)
  (edge : int edge)
  : loop =
  ...
  let from_, to_, weight = edge in
  match distance.(from_), distance.(to_) with
    ...
    | Some du, Some dv when du + weight < dv ->
      distance.(to_) <- Some (du + weight);
      ...
```

And for a graph with `NUM_NODES` nodes, we just run the above edges iteration a max of `NUM_NODES - 1` times:

```ocaml
let relax_distances (num_nodes : int) (edges : int edge list) (state : loop) (i : int)
  : [ `Continue of loop
    | `Stop of min_paths
    ] =
  let { paths ; is_updated } = state in
  if i = num_nodes - 1 then `Stop paths
  else
    let iter =
      List.fold_left relax_distance { paths ; is_updated } edges
    in
    if iter.is_updated then `Continue iter
    else `Stop paths
```

A common optimization is to early return when no distances were updated in some iteration. I implemented this using a `fold_until` style loop where we only ``Continue` the next relaxation iteration when the `is_updated` flag is set. This flag is set in an edges iteration when at least one shortest distance from the loop state is lowered. So when the relaxation condition described is hit, `is_updated` is set to true:

```ocaml
let relax_distance
  ...
  match distance.(from_), distance.(to_) with
  ...
  | Some du, Some dv when du + weight < dv ->
    distance.(to_) <- Some (du + weight);
    predecessor.(to_) <- Some { edge ; tail = from_ };
    { paths = ~distance, ~predecessor ; is_updated = true }
  ...
```

Along with when a distance was initially "discovered", which is the first case the `match` handles...

```ocaml
let relax_distance
  ...
  match distance.(from_), distance.(to_) with
  | Some du, None ->
    distance.(to_) <- Some (du + weight);
    predecessor.(to_) <- Some { edge ; tail = from_ };
    { paths = (~distance, ~predecessor) ; is_updated = true }
  ...
```

... where we favor using `None` over an integer max to represent the initial distances, because this is OCaml.

### Bellman Ford as a Difference Logic solver
Bellman Ford is significant to us because it solves our difference formulas. Recall that a difference literal is in the form:

```
(x - y) <> c
# Rewritten
(x <> y + c)
```

where `x` and `y` are either an int variable or the constant `0`, `c` is some constant, and `<>` is an operator that is one of:

```
<, <=, >, >=, =
```

We can encode an edge *from* `y` *to* `x` with cost `c` like so:

```mermaid
graph LR
  ny["y"] -->|"c"| nx["x"]
```

Referring back to our example:

```
(6 <= a) ^ (a < 0)
(0 - a <= -6) ^ (a - 0 <= -1)
```

The corresponding difference graph is:

```mermaid
graph LR
  n0["0"]
  na["a"]

  n0 -->|"-6"| na
  na -->|"-1"| n0
```

## An extra IDL formula case
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

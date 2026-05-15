# Programming Blue3: An SMT solver for Caprice-Lang
Blue3 is an SMT solver for JHU's [`caprice-lang`](https://github.com/JHU-PL-Lab/caprice-lang). It is used by its typechecker known as the [Concolic Evaluator](https://github.com/JHU-PL-Lab/caprice-lang/blob/main/docs/caprice.md), or `ceval`.

Before Blue3, `ceval` used [Z3](https://www.microsoft.com/en-us/research/project/z3-3/) to solve SMT formulas. `ceval` still uses Z3, but is now used as a fallback rather than being the sole solver for when Blue3 cannot solve the formula.

Z3 is more than capable of solving our formulas, of course, but the JHU Programming Language lab felt it was overkill for many of the cases. For instance, `ceval` might output something like:

$$
(6 \leq a) \land (a < 0)
$$

We say this formula is **unsatisfiable**, or UNSAT, because $a$ can't be $6$ or more while also being less than $0$.

The non-insigificant overhead of calling Z3 made an in-house solver for trivial cases seem like a promising way to improve `ceval`'s performance.

## Intro

This report introduces Blue3, a minimal SMT solver for caprice-lang. Although small, Blue3 implements a full solver pipeline using modern SAT/SMT techniques. In benchmarks, Blue3's frontend was just over 60% faster than Z3 on simple formulas.

| avg_blue3 | avg_z3 |
|-----------|--------|
| 222.0μs | 329.0μs |

When Blue3 cannot solve a formula, it falls back to Z3. This adds about 20.24μs of overhead on average, or roughly 5% compared to calling Z3 directly.

| num_slow_cases | avg_slower_by | avg_percent_slower |
|----------------|---------------|--------------------|
| 38 | 20.24μs | 4.59% |

This is a reasonable tradeoff: Blue3 solves simple formulas much faster, while still using Z3 as a backup.

Before discussing Blue3 itself, we first need some context on $P = NP$, SAT, and 3SAT.

### P = NP and Boolean Satisfiability

Oversimplifying, $P = NP$ asks:

> If we can check a solution quickly, can we also find that solution quickly?

Some problems are easy to solve and easy to check. For example, sorting a list like:

$$
[5, 2, 9, 1]
$$

into:

$$
[1, 2, 5, 9]
$$

can be done efficiently. Problems solvable in polynomial time are in the class $P$.

Other problems are harder to solve but easy to verify. Sudoku is the classic example: finding the solution may require search, but checking a completed board is straightforward. Problems whose solutions can be verified in polynomial time are in $NP$.

So another way to state $P = NP$ is:

> If a solution can be verified in polynomial time, can it also be found in polynomial time?

We do not know the answer. Most computer scientists believe $P \neq NP$, but no one has proven it.

This matters because some problems are **NP-complete**: they are in $NP$, and every other problem in $NP$ can be reduced to them in polynomial time. If we found a polynomial-time algorithm for one NP-complete problem, then every problem in $NP$ could be solved efficiently.

That would have massive consequences for optimization, science, and cryptography.

### 3SAT and Boolean Satisfiability

3SAT asks:

> Given a propositional formula in CNF with at most 3 literals per clause, is there some assignment that makes it true?

A formula is **satisfiable** if at least one assignment makes it true. For example:

$$
(p \lor q) \land (\neg p \lor \neg q)
$$

is satisfiable because this model works:

```json
{
  "p": true,
  "q": false
}
```

Plugging those values in gives:

$$
(\text{true} \lor \text{false}) \land (\neg \text{true} \lor \neg \text{false})
$$

which evaluates to true.

But this formula is unsatisfiable:

$$
(p \lor q) \land (\neg p \lor q) \land (p \lor \neg q) \land (\neg p \lor \neg q)
$$

No assignment of $p$ and $q$ can make every clause true at once.

3SAT is important because it is NP-complete. So if we could solve 3SAT in polynomial time, we would prove $P = NP$.

Blue3 obviously does not solve $P = NP$. Instead, it uses practical SAT/SMT techniques to solve many real formulas efficiently.

SMT solvers extend SAT by allowing richer theory constraints. For example:

$$
(6 \leq a) \land (a < 0)
$$

is not purely propositional, because it talks about integer inequalities. Blue3 maps theory atoms like these into propositional variables:

$$
p \land q
$$

where:

- $p$ represents $(6 \leq a)$
- $q$ represents $(a < 0)$

The SAT solver handles the propositional structure, while the theory solver checks whether the underlying constraints are actually consistent.

### Useful Terminology

A **formula** is a boolean-valued expression. In this report, unless stated otherwise, "formula" usually means a formula in **CNF**.

A formula in **CNF** is an AND of clauses:

$$
(p \lor q \lor r) \land (s \lor t \lor \neg u)
$$

A **clause** is one OR-group:

$$
(p \lor q \lor r)
$$

A **literal** is an atom with a sign. For example:

$$
p
$$

and:

$$
\neg p
$$

are both literals.

An **atom** is the unsigned condition underneath a literal. So $p$ and $\neg p$ refer to the same atom: $p$.

In SMT, atoms can be theory constraints, such as:

$$
a = 1
$$

or:

$$
a \neq 1
$$

We will use three main formula categories:

1. A **SAT formula** is purely propositional:

   $$
   p \land q
   $$

2. A **theory formula** is handled by a theory solver:

   $$
   (6 \leq a) \land (a < 0)
   $$

3. An **SMT formula** combines propositional logic with theory constraints:

   $$
   (6 \leq a) \land (a < 0) \land (r \lor s)
   $$

Finally, a **solver** takes a formula and returns either **SAT**, usually with a satisfying model, or **UNSAT**, meaning no satisfying assignment exists.

## Difference Logic

Recall that Blue3 is meant to handle formulas that are too simple to justify calling Z3, such as:

$$
(6 \leq a) \land (a < 0)
$$

The first challenge was deciding what “simple” meant for `caprice-lang` formulas. Since its formula AST only works over `bool`s and `int`s, we focused on the integer-heavy formulas that appeared often in our benchmarks:

| formula_id |            formula             | 
|------------|--------------------------------|
| 9          | (0 < a) ^ ((a + 1) <= a)       |
| 8          | (0 < a) ^ ((a + 1) <= 1)       |
| 56         | (not (a = 0)) ^ ((a + 10) = 0) |
| 11         | (1 < a) ^ (a < 0)              |
| 88         | (0 < a) ^ (a < 1)              |

This led us to **Integer Difference Logic**, or **IDL**, a fragment of linear integer arithmetic where constraints compare the difference between two integer terms. In SMT-LIB terms, IDL is a sub-logic of Linear Integer Arithmetic over the `Ints` theory.

More formally, an IDL solver decides satisfiability for literals shaped like:

$$
(x \leq y) \text{<>} c
$$

Here, $x$ and $y$ are integer variables or the constant $0$, $c$ is an integer constant, and $<>$ is one of $<, \leq, >, \geq,$ or $=$. IDL does **not** directly handle $\neq$, nor sums like $x + y$ or any other operator other than $-$ for that matter.

Many of our “simple” formulas fit this difference form, including:

$$
(6 \leq a) \land (a < 0)
$$

We can rewrite it as:

$$
((0 - a) \leq -6) \land ((a - 0) \leq -1)
$$

This rewriting looks unnecessary to us because we can immediately see the contradiction: $a$ cannot be both at least $6$ and less than $0$. But IDL gives our computer a precise way to recognize that contradiction mechanically.

It turns out there is a natural graph interpretation of IDL, where each difference constraint becomes an edge, and satisfiability can be checked with a shortest-path algorithm.

### Bellman-Ford

Bellman-Ford finds the shortest paths from one source node to every other node in a directed weighted graph. It also detects **negative cycles**, which are cycles whose total weight is negative.

For example:

```{.ocaml #simple-no-neg-intro}
let simple_no_neg =
  [ ("a", "0*", 3) ; ("0*", "a", -1)
  ; ("r", "0*", 9) ; ("r", "a", 5)
  ] in
print_mermaid_lr ~id:"simple-no-neg" simple_no_neg;
```

```{.mermaid #simple-no-neg-mermaid}
graph LR
  na["a"] -->|"3"| n0_["0*"]
  n0_["0*"] -->|"-1"| na["a"]
  nr["r"] -->|"9"| n0_["0*"]
  nr["r"] -->|"5"| na["a"]
```

Running Bellman-Ford from `r` gives:

| Node | Distance |
|------|----------|
| $a$ | $5$ |
| $0^*$ | $8$ |

The shortest path to `a` is:

$$
r \to a
$$

with cost $5$. The shortest path to $0^*$ is:

$$
r \to a \to 0^*
$$

with cost:

$$
5 + 3 = 8
$$

This beats the direct edge $r \to 0^*$, which costs $9$.

The cycle between `a` and $0^*$ has cost:

$$
3 + (-1) = 2
$$

Since the cycle is positive, looping only makes paths more expensive. So there is **no negative cycle**.

Now change the edge $0^* \to a$ from $-1$ to $-4$:

```{.ocaml #print-simple-neg}
let simple_neg =
  [ ("a", "0*", 3) ; ("0*", "a", -4)
  ; ("r", "0*", 9) ; ("r", "a", 5)
  ] in
print_mermaid_lr ~id:"simple-neg-mermaid" simple_neg;
print_bellman_ford ~label:"simple-neg-bf" ~src:"r" simple_neg
```

Now the cycle cost is:

$$
3 + (-4) = -1
$$

Each loop makes the path cheaper, so there is no true shortest path. Bellman-Ford reports:

```txt
Negative cycle found!
```

```{.mermaid #simple-neg-bf}
graph LR
  n0*["0*"] -->|"-4"| na["a"]
  na["a"] -->|"3"| n0*["0*"]
```

#### Relaxing Edges

Bellman-Ford repeatedly loops over every edge and tries to improve the known distance to each node. This update step is called **relaxation**.

An edge is relaxed when:

$$
dist[from] + cost < dist[to]
$$

In code:

```{.ocaml #relax-edge-cases}
let relax_edge tbl was_updated edge =
  let from_, to_, cost = edge in
  match Hashtbl.find tbl from_, Hashtbl.find tbl to_ with
  | (Some du, _), (None, _) ->
    set_distance to_ tbl ~min:(du + cost) ~pred:edge
  | (Some du, _), (Some dv, _) when du + cost < dv ->
    set_distance to_ tbl ~min:(du + cost) ~pred:edge
  | _ -> was_updated
```

The table starts with every node at infinity, represented by `None`, except the source, which starts at distance `0`.

```{.ocaml #create-distance-table}
let create_tbl ~src edges =
  let tbl =
    edges
    |> to_node_list
    |> ...
  in
  Hashtbl.replace tbl src (Some 0, None);
  tbl
```

Bellman-Ford relaxes all edges at most $N - 1$ times, where $N$ is the number of nodes:

```{.ocaml #relax-edges-stop-case}
let relax_edges edges dist i =
  if i >= Hashtbl.length dist - 1 then `Stop dist
  else ...
```

We also stop early if a full pass over the edge list does not update anything:

```{.ocaml #relax-edges-early-stop}
let is_dist_updated = List.fold_left (relax_edge dist) false edges in
if is_dist_updated then `Continue dist
else `Stop dist
```

So the core algorithm is:

```{.ocaml #find-shortest-paths}
let find_shortest_paths ~src edges =
  let dist = create_tbl ~src edges in
  ...
  List_utils.fold_until
    (relax_edges edges)
    Fun.id
    dist
    vertices
```

#### Predecessors

Each table entry stores both the current shortest-known distance and the predecessor edge that produced it:

```{.ocaml #distance-predecessor-state}
(distance, predecessor_edge)
```

The distance tells us the cost from `src`; the predecessor edge lets us reconstruct the path.

For the earlier graph, the shortest path to `a` is direct:

```txt
Minimum distance to "a" = 5
Predecessor edge of "a" is = r -> a (5)
```

The shortest path to $0^*$ goes through `a`:

```txt
Minimum distance to "0*" = 8
Predecessor edge of "0*" is = a -> 0* (3)
```

Tracing predecessors gives:

$$
r \to a \to 0^*
$$

So one predecessor edge per node is enough to reconstruct a shortest path.

#### Detecting Negative Cycles

After the normal relaxation loop, Bellman-Ford runs one extra pass over the edges. If any edge can still be relaxed, then the graph has a negative cycle.

```{.ocaml #find-relaxed-node-opt}
let find_relaxed_node_opt edges dist =
  List.find_map
    (fun ((_, to_, _) as edge) ->
      if relax_edge dist false edge then Some to_
      else None)
    edges
```

The relaxed node proves a negative cycle exists, but it may not itself be inside the cycle. For example:

```{.ocaml #relnode-not-in-neg-cycle}
let relnode_not_in_neg_cycle =
  [ ("c", "d", 0) ; ("s", "a", 0)
  ; ("a", "b", 1) ; ("b", "c", -4)
  ; ("c", "a", 1)
  ] in
print_mermaid_lr ~id:"relnode-not-in-neg-cycle-mermaid" relnode_not_in_neg_cycle;
```

```{.mermaid #relnode-not-in-neg-cycle-mermaid}
graph LR
  nc["c"] -->|"0"| nd["d"]
  ns["s"] -->|"0"| na["a"]
  na["a"] -->|"1"| nb["b"]
  nb["b"] -->|"-4"| nc["c"]
  nc["c"] -->|"1"| na["a"]
```

Here, the first relaxed node can be `d`, even though `d` is only reached from the cycle:

```txt
Relaxed: d
```

To guarantee we land inside the cycle, we follow predecessor links `NUM_NODES` times. By the pigeonhole principle, this skips any non-cycle tail.

```{.ocaml #find-cycle-entry-opt}
let find_cycle_entry_opt edges (tbl, num_nodes) =
  match find_relaxed_node_opt edges tbl with
  | None -> None
  | Some entry ->
    let rec move_back node n =
      if n = 0 then node
      else
        match find_predecessor node tbl with
        | None -> node
        | Some from_ -> move_back from_ (n - 1)
    in
    Some (move_back entry num_nodes)
```

Then we collect predecessor edges until we return to the start node:

```{.ocaml #collect-cycle}
let collect_cycle start (tbl, num_nodes) =
  let rec loop curr n acc =
    if n = 0 then acc
    else
      match find_predecessor_edge curr tbl with
      | None -> acc
      | Some ((from_, _, _) as pred_edge) ->
        let acc = pred_edge :: acc in
        if Node.compare from_ start = 0 then acc
        else loop from_ (n - 1) acc
  in
  loop start num_nodes []
```

In short, Bellman Ford's steps are:

1. Compute the distance table.
2. Run one extra relaxation pass.
3. If nothing changes, return the distances.
4. If something changes, backtrack predecessors and return the negative cycle.

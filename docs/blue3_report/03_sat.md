## SAT
3SAT was the first problem shown to be $\text{NP-complete}$, which means it is in $\text{NP}$ and every other problem in $\text{NP}$ can be reduced to it in polynomial time.

Skipping a ton of boolean algebra, the generalized $\text{k-SAT}$ problem asks:

> Given a formula with at most $k$ literals in each clause, can we determine its satisfiability quickly?

So given a formula like:

```math
(p \lor q \lor \neg{r}) \land (\neg{p} \lor r) \land (q \lor r) \land \neg{r}
```

k-SAT is asking whether truth values for $p, q,$ and $r$ exists so that when we substitute those values in we get a `true`, and if we can determine that quickly, which for our purposes, just means polynomial time.

It turns out this is satisfiable, because:

```json
{
    "p": false,
    "q": true,
    "r": false
}
```

```math
    (\text{false} \lor \text{true} \lor \neg{false}) \land (\neg{\text{false}} \lor {\text{false}}) \land (\text{true} \lor \text{false}) \land \neg{\text{false}}
```

At the time of writing, we don't have a way to solve problems like this in polynomial time. So our fastest algorithms today are effectively a "smart" brute-force algorithm.

### Conflict Driven Clause Learning

Blue3 uses the Conflict-Driven-Clause-Learning, or `CDCL` for short, to handle solving boolean formulas. Although `CDCL` can be boiled down to a "smart" guessing and checking loop, we'll see that it is "smart" enough to make most formulas solvable in a reasonable amount of time.

One way it is "smart" is that it knows when a literal is required to be true for the formula to be satisfiable. If you were given the formula:

```math
p \land \neg{q} \land (\neg{p} v q v \neg{r})
```

Even if you don't know whether it's satisfiable from a glance, you can probably infer quickly that at the very least, *if* there were a satisfiable model for this, *then* it must have $p = \text{true}$ and $q = \text{false}$ because they are the only literal in their (implicit) clause. In other words, we can infer the required truth values for $p$ and $q$ because they are both **unit clauses**. CDCL can figure this out, too, through a procedure known as Unit Propagation.

The CDCL loop (sometimes calls Boolean Constraint Propagation, or `bcp`) always begins with Unit Propagation, where it scans the clause list for any unit clauses:

```ocaml (sat/cdcl.ml:49)
let rec bcp (level : int) (trail : Trail.trail) (formula : Formula.formula) : Model.model option =
  begin match unit_propagate formula trail with
  ...
```

Where `unit_propagate` accepts the propositional **`formula`** along with the current search state encoded in `trail` (more on that soon) and returns a union `next` type that tells `bcp` the next step it should take in the loop:

```ocaml
let unit_propagate formula model =
  let rec search_empty
    ...
  in
  let rec search_unit (formula : Formula.formula) : next =
    ...
  in
  search_unit formula
```

This calls 2 local recursive functions `search_empty` and `search_unit`, and it begins by calling `search_unit`.

If `search_unit`
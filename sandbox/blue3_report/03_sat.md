# SAT
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

Blue3 uses the Conflict-Driven-Clause-Learning, or `CDCL` for short, to handle solving boolean formulas. Although `CDCL` can be boiled down to a "smart" guessing and checking procedure, we'll see that it is "smart" enough to make most formulas solvable in a reasonable amount of time.

## Conflict Driven Clause Learning
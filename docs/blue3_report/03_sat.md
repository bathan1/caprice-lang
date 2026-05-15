## SAT

3SAT was the first problem shown to be $\text{NP-complete}$, which means it is in $\text{NP}$ and every other problem in $\text{NP}$ can be reduced to it in polynomial time.

Skipping a ton of boolean algebra, the generalized $\text{k-SAT}$ problem asks:

> Given a formula with at most $k$ literals in each clause, can we determine its satisfiability quickly?

So given a formula like:

```math
(p \lor q \lor \neg{r}) \land (\neg{p} \lor r) \land (q \lor r) \land \neg{r}
```

$k$-SAT is asking whether truth values for $p, q,$ and $r$ exist so that when we substitute those values in, the whole formula evaluates to `true`. When we ask whether we can determine that "quickly," we usually mean whether we can solve it in polynomial time.

It turns out this formula is satisfiable, because:

```json
{
    "p": false,
    "q": true,
    "r": false
}
```

Substituting those values gives us:

```math
(\text{false} \lor \text{true} \lor \neg{\text{false}})
\land
(\neg{\text{false}} \lor \text{false})
\land
(\text{true} \lor \text{false})
\land
\neg{\text{false}}
```

which simplifies to `true`.

At the time of writing, we do not have a known way to solve SAT in polynomial time. So our fastest algorithms today are still, at a high level, "smart" brute-force algorithms.

### Conflict-Driven Clause Learning

Blue3 uses **Conflict-Driven Clause Learning**, or `CDCL` for short, to handle solving boolean formulas. Although `CDCL` can be simplified down to a "smart" guessing-and-checking loop, it is smart enough to make many formulas solvable in a reasonable amount of time.

The rough structure of CDCL is:

1. Use the current assignments to infer anything that must be true.
2. If nothing can be inferred, make a guess.
3. If the guess causes a contradiction, learn from the contradiction.
4. Repeat until we either find a satisfying assignment or prove that no assignment exists.

In Blue3, this loop is implemented in `bcp`:

```ocaml
let rec bcp (level : int) (trail : Trail.trail) (formula : Formula.formula) : Solution.solution =
  begin match unit_propagate formula trail with
  ...
```

The first thing the loop does is call `unit_propagate`.

### Unit Propagation

One way CDCL is "smart" is that it can identify when a literal is forced to be true.

For example, suppose we have:

```math
p \land \neg{q} \land (\neg{p} \lor q \lor \neg{r})
```

Even if we do not know from a glance whether the whole formula is satisfiable, we can immediately infer that any satisfying assignment must have:

```math
p = \text{true}
```

and:

```math
q = \text{false}
```

because $p$ and $\neg{q}$ appear by themselves. These are called **unit clauses**.

A unit clause is a clause with exactly one unassigned literal and no currently satisfied literal. Since a CNF formula is an $\land$ of clauses, every clause must eventually be true. So if a clause only has one possible literal left that could make it true, CDCL can safely assign that literal.

In Blue3, this is handled by `unit_propagate`:

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

This function takes the current propositional `formula` and the current `model`, then returns a `next` value telling the CDCL loop what to do next.

It begins with `search_unit`:

```ocaml
let rec search_unit (formula : Formula.formula) : next =
  match formula with
  | [] -> Decide
```

If there are no clauses left to inspect, then there is nothing to propagate and no immediate conflict. So `unit_propagate` returns `Decide`, meaning CDCL needs to make a guess.

Otherwise, `search_unit` checks the current clause:

```ocaml
match formula with
| [] -> Decide
| clause :: clauses' ->
  match Model.eval_clause clause model with
  | `Falsified -> Conflict clause
  | `Undecided [lit] -> search_empty clauses' clause lit
  | _ -> search_unit clauses'
```

There are three important cases here.

First, the clause might already be falsified:

```ocaml
| `Falsified -> Conflict clause
```

A `clause` is a list of disjuncted $\lor$ terms. Since it is an OR, only one literal needs to be true for the whole clause to be true.

So we say a clause is **falsified** if every literal in the clause has already been assigned a value, and every one of those literals evaluates to false under the current model.

For example, consider:

```math
(p \lor \neg{q} \lor r)
```

If our current model is:

```json
{
    "p": false,
    "q": true,
    "r": false
}
```

then the clause becomes:

```math
(\text{false} \lor \neg{\text{true}} \lor \text{false})
```

which simplifies to:

```math
(\text{false} \lor \text{false} \lor \text{false})
```

So the clause is falsified.

In CDCL, a falsified clause means the solver has found a contradiction in the current assignment. Since a CNF formula is an $\land$ of clauses, every clause needs to be satisfied. If even one clause is false, then the whole formula is false under the current model.

So if `eval_clause` tells us that the current clause is falsified, `unit_propagate` returns that clause as a `Conflict`.

The second important case is when the clause is undecided, but has exactly one unassigned literal left:

```ocaml
| `Undecided [lit] -> search_empty clauses' clause lit
```

This means the clause is not satisfied yet, but there is only one remaining literal that could possibly make it true. So CDCL can infer that this literal must be assigned.

For example, suppose we have:

```math
(\neg{p} \lor q \lor r)
```

and our model currently says:

```json
{
    "p": true,
    "q": false
}
```

Then the clause becomes:

```math
(\neg{\text{true}} \lor \text{false} \lor r)
```

which simplifies to:

```math
(\text{false} \lor \text{false} \lor r)
```

So if this clause is going to be satisfied, we must have:

```math
r = \text{true}
```

That is unit propagation.

One small optimization in Blue3 is that once we find a unit clause, we do not keep searching for other unit clauses. We already have one valid implication to return. However, we still keep scanning the rest of the formula to make sure there is not already a conflict somewhere later.

That is what `search_empty` is for: it remembers the unit implication we found, but keeps checking whether a conflict should take priority.

### Deciding

Eventually, unit propagation may reach a point where it cannot infer anything else.

For example, suppose the formula is:

```math
(p \lor q) \land (\neg{p} \lor r)
```

At the start, there are no unit clauses. None of these clauses force a specific assignment yet. In this case, `unit_propagate` returns:

```ocaml
Decide
```

This tells CDCL:

> I cannot infer anything else right now. Pick an unassigned variable and guess a value.

That guess is called a **decision**.

For example, CDCL might decide:

```math
p = \text{true}
```

After making that decision, it runs unit propagation again. This is where the loop becomes useful. A single guess can create new unit clauses, which then create more forced assignments.

Using the formula:

```math
(p \lor q) \land (\neg{p} \lor r)
```

if we decide:

```math
p = \text{true}
```

then the first clause is already satisfied:

```math
(\text{true} \lor q)
```

but the second clause becomes:

```math
(\neg{\text{true}} \lor r)
```

which simplifies to:

```math
(\text{false} \lor r)
```

So now unit propagation forces:

```math
r = \text{true}
```

At this point, CDCL has built a partial model:

```json
{
    "p": true,
    "r": true
}
```

If every clause is satisfied, then CDCL can return `SAT`.

### Conflicts

Sometimes a decision leads to a contradiction.

Consider this formula:

```math
(p \lor q) \land (\neg{p} \lor q) \land (p \lor \neg{q}) \land (\neg{p} \lor \neg{q})
```

There are no unit clauses at the beginning, so CDCL has to make a decision.

Suppose it decides:

```math
p = \text{true}
```

Then the second clause becomes:

```math
(\neg{p} \lor q) \equiv (\text{false} \lor q)
```

So unit propagation forces:

```math
q = \text{true}
```

Now the current model is:

```json
{
    "p": true,
    "q": true
}
```

But now consider the fourth clause:

```math
(\neg{p} \lor \neg{q})
```

Substituting in the current model gives:

```math
(\neg{\text{true}} \lor \neg{\text{true}})
```

which simplifies to:

```math
(\text{false} \lor \text{false})
```

So we have a conflict.

The current assignment cannot possibly satisfy the formula, because it already falsifies one of the clauses.

A very basic brute-force solver would just backtrack and try another assignment (which is what the original DPLL algorithm CDCL was based on did). CDCL does something smarter: it analyzes the conflict and learns a new clause that prevents it from repeating the same mistake.

In this tiny example, the conflict came from assigning both:

```math
p = \text{true}
```

and:

```math
q = \text{true}
```

So CDCL can learn that this combination is bad:

```math
\neg{p} \lor \neg{q}
```

In this example, that clause already exists in the formula, but in larger examples CDCL can learn new clauses that were not written explicitly in the original input.

This is the "clause learning" part of Conflict-Driven Clause Learning.

### A full example

Let's consider an example where CDCL makes a bad decision, hits a conflict, backtracks, and then finds a satisfying assignment, to see how the loop works all together.

Consider the satisfiable formula:

```math
(p \lor q) \land (\neg{p} \lor r) \land (\neg{r} \lor q)
```

In Blue3, the CDCL loop starts here:

```ocaml
let cdcl formula = bcp 0 [] formula
```

where `0` is the starting decision level and `[]` is the empty trail, meaning we have not assigned any literals yet.

Inside `bcp`, we first turn the trail into a model and call `unit_propagate`:

```ocaml
let rec bcp (level : int) (trail : Trail.trail) (formula : Formula.formula) : Solution.solution =
  let model = Trail.to_model trail in
  begin match unit_propagate formula model with
  | Decide -> ...
  | Conflict clause -> ...
  | Implication (clause, lit) -> ...
  end
```

At the beginning, there are no unit clauses, so `unit_propagate` returns:

```ocaml
Decide
```

That sends us into the `Decide` branch:

```ocaml
| Decide ->
  let atoms = List.map Formula.atom_from_literal model in
  begin match Formula.find_free_variable_opt atoms formula with
  | None ->
    if Model.is_tautology formula model then SAT model
    else UNSAT
  | Some x ->
      decide ~lit:(Formula.pos x) level trail formula
  end
```

Since the formula still has unassigned variables, CDCL chooses one. In this implementation, it just picks a free variable and tries its positive literal first:

```ocaml
decide ~lit:(Formula.pos x) level trail formula
```

As the comment in the code says, this choice is arbitrary:

```ocaml
(* [Formula.pos x] is arbitrary. It doesn't matter because the
   learned conflicts forces the loop to terminate (at some point).

   Smarter heuristics could be implemented in the future... *)
```

For this example, suppose CDCL makes the bad decision:

```math
q = \text{false}
```

This is added to the trail as a decision at the next decision level:

```ocaml
and decide ~lit level trail =
  let next_lvl = level + 1 in
  let trail' = Trail.decided ~lit next_lvl trail in
  bcp next_lvl trail'
```

Now CDCL runs `bcp` again, but this time the model contains:

```json
{
    "q": false
}
```

With that assignment, the first clause:

```math
(p \lor q)
```

now only has one way left to become true: $p$ must be true. So `unit_propagate` returns an implication:

```ocaml
Implication (clause, lit)
```

Conceptually, this means:

> Because of this clause, this literal must be assigned.

In code, Blue3 records that implication in the trail:

```ocaml
| Implication (clause, lit) ->
  let trail' = Trail.imply ~reason:clause level lit trail in
  bcp level trail' formula
```

So after seeing:

```math
(p \lor \text{false})
```

the solver implies:

```math
p = \text{true}
```

Now the trail/model contains:

```json
{
    "q": false,
    "p": true
}
```

Then the second clause:

```math
(\neg{p} \lor r)
```

also becomes unit, because $p = \text{true}$. So CDCL implies:

```math
r = \text{true}
```

Now the model is:

```json
{
    "q": false,
    "p": true,
    "r": true
}
```

But now the third clause is impossible to satisfy:

```math
(\neg{r} \lor q)
```

because $r = \text{true}$ and $q = \text{false}$. So the clause evaluates to false.

At that point, `unit_propagate` returns:

```ocaml
Conflict clause
```

and `bcp` enters the conflict branch:

```ocaml
| Conflict clause ->
  let clause', backtrack_lvl = Trail.analyze_conflict ~clause level trail in
  if backtrack_lvl < 0 then UNSAT
  else backtrack_learn ~level:backtrack_lvl clause' trail formula
```

This is the part that makes CDCL different from plain backtracking. What makes CDCL different from its predecessor DPLL is that in DPLL, we would just reverse the last decision of `r = true` and try `r = false`, when the real reason behind our contradiction was a previous decision of `q = false`.

So it resolves that "real reason" via `analyze_conflict`:

```ocaml
Trail.analyze_conflict ~clause level trail
```

This analyzes the trail and returns two things:

```ocaml
let clause', backtrack_lvl = Trail.analyze_conflict ~clause level trail
```

The new learned clause, `clause'`, records what the solver learned from the conflict. The `backtrack_lvl` tells the solver which decision level it should jump back to.

This works because Blue3's trail stores more than just the assigned literals. Each trail entry also records the decision level and the reason why that literal was assigned:

```ocaml
type reason =
  | Decided
  | Propagated of literal list

type step = { level : int ; lit : literal ; reason : reason }

type trail = step list
```

So when `analyze_conflict` receives the conflict clause, it can walk backward through the trail and ask: "Which literals in this conflict were assigned at the current decision level, and were they decided directly or propagated by another clause?" If there is more than one current-level literal involved in the conflict, Blue3 finds the propagation reason for one of them and resolves the conflict clause with that reason:

```ocaml
| current_level_lits ->
  let reason = find_reason current_level_lits trail in
  let clause' = Formula.resolve_pair clause reason in
  analyze_conflict ~clause:clause' level trail
```

This repeats until the learned clause has exactly one literal from the current decision level:

```ocaml
match List.filter (fun lit -> find_level lit trail = level) clause with
| [hd] ->
  ...
```

At that point, the solver has found a useful learned clause. The clause itself becomes `clause'`, and the backtrack level is computed as the highest decision level among the remaining literals in that learned clause:

```ocaml
let new_lvl =
  clause
  |> List_utils.remove1 hd
  |> List.fold_left
      (fun lvl' lit ->
        max lvl' (find_level lit trail)) 0
in
clause, new_lvl
```

So `analyze_conflict` returns:

```ocaml
clause, new_lvl
```

where `clause` is the learned clause, and `new_lvl` is the decision level Blue3 should jump back to.

If the conflict is impossible to escape from, `backtrack_lvl` is negative:

```ocaml
if backtrack_lvl < 0 then UNSAT
```

That means the formula is unsatisfiable.

But in this example, the formula is satisfiable. The issue was just the bad decision:

```math
q = \text{false}
```

So Blue3 backtracks and learns the new clause:

```ocaml
else backtrack_learn ~level:backtrack_lvl clause' trail formula
```

The implementation is short:

```ocaml
and backtrack_learn ~level clause trail formula =
  let trail' = Trail.backjump ~level trail in
  let formula' = clause :: formula in
  bcp level trail' formula'
```

There are two key things happening here:

1. `Trail.backjump ~level trail` removes assignments after the chosen backtrack level.
2. `clause :: formula` adds the learned clause to the formula, so CDCL will not repeat the same bad branch.

In this specific example, the learned clause `clause'` would be:

```math
q
```

Here is why. The conflict clause is:

```math
(\neg{r} \lor q)
```

because this was the clause that became false under:

```json
{
    "q": false,
    "p": true,
    "r": true
}
```

But `r = true` was not guessed directly. It was propagated from:

```math
(\neg{p} \lor r)
```

So conflict analysis resolves:

```math
(\neg{r} \lor q)
```

with:

```math
(\neg{p} \lor r)
```

which removes the opposite pair $r$ and $\neg{r}$, giving:

```math
(q \lor \neg{p})
```

Then `p = true` was also propagated, this time from:

```math
(p \lor q)
```

So conflict analysis resolves:

```math
(q \lor \neg{p})
```

with:

```math
(p \lor q)
```

which removes the opposite pair $p$ and $\neg{p}$, giving:

```math
q
```

So the learned clause is just:

```math
q
```

In code, this is the value that gets appended onto the formula:

```ocaml
let formula' = clause :: formula
```

So after conflict analysis, the formula effectively becomes:

```math
q \land (p \lor q) \land (\neg{p} \lor r) \land (\neg{r} \lor q)
```

This means Blue3 has learned:

> The branch where `q = false` cannot work, so from now on `q` must be true.

Then `Trail.backjump ~level trail` backjumps to level `0`, and the newly learned unit clause `q` immediately forces:

```math
q = \text{true}
```

After backtracking, CDCL continues solving now knowing that:

```math
q = \text{true}
```

With $q = \text{true}$, the first clause is satisfied:

```math
(p \lor \text{true})
```

and the third clause is also satisfied:

```math
(\neg{r} \lor \text{true})
```

Now the only clause that still matters is:

```math
(\neg{p} \lor r)
```

A satisfying model is:

```json
{
    "q": true,
    "p": false
}
```

because then the formula becomes true regardless of what $r$ is.

So after the conflict, backtracking, and learning step, CDCL eventually returns:

```text
SAT
```

The important idea is that a conflict does not always mean the whole formula is unsatisfiable. Sometimes it only means:

> The current branch of guesses cannot work.

In that case, CDCL uses the conflict to learn a new clause, backjumps to an earlier decision level, and keeps searching from there.

### From SAT to SMT

So far, everything we have discussed has been purely propositional. The variables are just booleans like $p$, $q$, and $r$, and the solver only needs to decide whether each one is `true` or `false`.

However, Blue3 is not only trying to solve boolean formulas. It is trying to solve formulas that contain domain-specific constraints, such as integer (difference) comparisons:

```math
(6 \le a) \land (a < 0)
```

A SAT solver by itself does not understand what $6 \le a$ or $a < 0$ means. It can only treat each expression as a plain boolean.

So the next step is to connect the SAT solver to a theory solver. The SAT solver handles the boolean structure of the formula, while the theory solver checks whether the chosen boolean assignment actually makes sense in the underlying theory.

This is where Blue3 moves from SAT solving into SMT solving.
## SMT

So far, we have looked at two separate pieces of Blue3:

1. The **SAT solver**, which understands boolean structure like:

```math
p \land (\neg{p} \lor q)
```

2. The **IDL solver**, which understands integer difference constraints like:

```math
x - y \le c
```

The problem is that Blue3 is not only trying to solve purely boolean formulas or purely IDL formulas. It is trying to solve formulas that mix both together.

For example:

```math
(6 \le a) \land (a < 0)
```

This formula is obviously unsatisfiable if we understand integer arithmetic. But to a SAT solver, the expressions `6 <= a` and `a < 0` are just boolean-looking things. The SAT solver does not know what they mean.

So the goal of the SMT layer is to combine both perspectives:

> Let the SAT solver handle the boolean structure, and let the theory solver check whether the chosen boolean assignment actually makes sense in the theory.

In Blue3, this is handled by the `cdcl_T` loop.

### Theory atoms

The first thing Blue3 does is represent theory-level boolean expressions as `Theory.atom`s:

```ocaml
type 'k atom =
  | Bool_key of (bool, 'k) Symbol.t
  | Predicate : ('a * 'a * bool) Binop.t * ('a, 'k) Formula.t * ('a, 'k) Formula.t -> 'k atom
```

A `Theory.atom` is anything that returns a boolean value inside an SMT formula.

So a plain boolean variable like:

```math
p
```

becomes:

```ocaml
Bool_key p
```

while an arithmetic predicate like:

```math
a < 0
```

becomes:

```ocaml
Predicate (Less_than, a, 0)
```

Then, just like SAT literals, theory literals can be positive or negative:

```ocaml
type 'k literal =
  | Pos of 'k atom
  | Neg of 'k atom
```

So:

```math
a < 0
```

becomes something like:

```ocaml
Pos (Predicate (Less_than, a, 0))
```

and:

```math
\neg(a < 0)
```

becomes:

```ocaml
Neg (Predicate (Less_than, a, 0))
```

A theory solver then receives a list of these literals:

```ocaml
type 'k theory_solver = 'k literal list -> 'k theory_solution
```

The important assumption is that this list is interpreted as a conjunction. So if the theory solver receives:

```ocaml
[lit1; lit2; lit3]
```

that means it should check:

```math
lit_1 \land lit_2 \land lit_3
```

### Theory results

A theory solver can return one of four results:

```ocaml
type 'k theory_solution =
  | Theory_unknown
  | Theory_sat of 'k Model.t
  | Theory_unsat of 'k core
  | Theory_split of 'k formula
```

Each result means something different.

If it returns:

```ocaml
Theory_sat model
```

then the current theory literals are consistent, and the theory solver found a concrete model.

If it returns:

```ocaml
Theory_unsat core
```

then the current theory literals are inconsistent. The `core` is the subset of literals that caused the contradiction.

If it returns:

```ocaml
Theory_split formula
```

then the theory solver is saying:

> I cannot decide this literal directly yet. Add these extra clauses to the SAT solver and try again.

This is especially useful for cases like disequality over integers:

```math
x \ne y
```

because in IDL, a disequality needs to be split into cases:

```math
x \le y - 1
```

or:

```math
y + 1 \le x
```

And if it returns:

```ocaml
Theory_unknown
```

then Blue3 gives up on this internal theory solver and lets the next solver handle the formula.

### Boolean abstraction

The SAT solver cannot directly reason about theory atoms. So Blue3 first abstracts every theory atom into a fresh SAT atom.

This is handled by the `connector` type.

```ocaml
type 'k connector =
  { to_sat : ('k Theory.atom, Sat.Formula.atom) Hashtbl.t
  ; from_sat : (Sat.Formula.atom, 'k Theory.atom) Hashtbl.t
  ; mutable count : int
  }
```

The connector stores two maps:

1. `to_sat`, which maps theory atoms to SAT atoms.
2. `from_sat`, which maps SAT atoms back to theory atoms.

So if Blue3 sees a theory atom like:

```math
6 \le a
```

it might assign it a fresh SAT variable like:

```math
p_1
```

And if it sees:

```math
a < 0
```

it might assign it:

```math
p_2
```

This is done by `abstract_atom`:

```ocaml
let abstract_atom
    ?uid
    (atom : 'k Theory.atom)
    (conn : 'k connector)
  : Sat.Formula.atom =
  match Hashtbl.find_opt conn.to_sat atom with
  | Some uid -> uid
  | None ->
      let sat_atom = next_uid ?uid conn in
      Hashtbl.add conn.to_sat atom sat_atom;
      Hashtbl.add conn.from_sat sat_atom atom;
      sat_atom
```

If the theory atom has already been seen before, Blue3 reuses the same SAT atom. Otherwise, it creates a fresh one and records the mapping in both directions.

Then theory literals are abstracted into SAT literals:

```ocaml
let abstract_literal
    ?uid
    (lit : 'k Theory.literal)
    (conn : 'k connector)
  : Sat.Formula.literal =
  match lit with
  | Neg smt_atom -> Sat.Formula.neg (abstract_atom ?uid smt_atom conn)
  | Pos smt_atom -> Sat.Formula.pos (abstract_atom ?uid smt_atom conn)
```

So a positive theory literal becomes a positive SAT literal, and a negative theory literal becomes a negative SAT literal.

### The CDCL(T) loop

The main SMT loop is `cdcl_T`:

```ocaml
let cdcl_T ~(solver : 'k Theory.theory_solver) (formula : (bool, 'k) Formula.t)
  : 'k Solution.t =
  let conn = make 64 in
  let propositional = abstract (Theory.from_smt_formula formula) conn in
  let rec loop conn sat_formula =
    match Sat.Cdcl.cdcl sat_formula with
    | UNSAT -> Solution.Unsat
    | SAT model ->
      let theory_lits =
        make_theory_literals model conn
      in
      match solver theory_lits with
      | Theory_unknown -> Solution.Unknown
      | Theory_unsat core ->
        let learned = theory_learn core conn in
        let sat_formula' = Sat.Formula.conjoin1 learned sat_formula in
        loop conn sat_formula'
      | Theory_sat model -> Solution.Sat model
      | Theory_split clauses ->
        let sat_formula' =
          List.fold_left
            (fun acc clause ->
              let sat_clause = abstract_clause clause conn in
              Sat.Formula.conjoin1 sat_clause acc)
            sat_formula
            clauses
        in
        loop conn sat_formula'
  in
  loop conn propositional
```

At a high level, this loop does the following:

1. Convert the SMT formula into a propositional SAT formula.
2. Run CDCL on the SAT formula.
3. If SAT says `UNSAT`, the whole formula is `UNSAT`.
4. If SAT finds a boolean model, convert that boolean model back into theory literals.
5. Ask the theory solver whether those theory literals are actually consistent.
6. If the theory solver says `SAT`, return the theory model.
7. If the theory solver says `UNSAT`, learn a new SAT clause and try again.
8. If the theory solver says `SPLIT`, add the split clauses and try again.

This is why it is called `CDCL(T)`: it is CDCL plus a theory solver `T`.

### Working through an example

Consider the formula:

```math
(6 \le a) \land (a < 0)
```

From the IDL section, we know this is unsatisfiable.

First, Blue3 converts this into theory atoms. Internally, these are predicates:

```ocaml
Predicate (Less_than_eq, 6, a)
Predicate (Less_than, a, 0)
```

Then the connector abstracts each theory atom into a SAT atom. We can imagine the mapping looking like this:

```text
p1 := (6 <= a)
p2 := (a < 0)
```

So the SAT-level formula becomes:

```math
p_1 \land p_2
```

The SAT solver does not know anything about integers, but it can easily satisfy this boolean formula by assigning:

```json
{
    "p1": true,
    "p2": true
}
```

So `Sat.Cdcl.cdcl sat_formula` returns:

```ocaml
SAT model
```

Then Blue3 converts the SAT model back into theory literals:

```ocaml
let theory_lits =
  make_theory_literals model conn
```

The implementation uses the `from_sat` map to recover the original theory atom:

```ocaml
let make_theory_literal (sat_model : Sat.Formula.literal list) (sat_atom : Sat.Formula.atom) (conn : 'k t) : 'k Theory.literal =
  let smt_atom = Hashtbl.find conn.from_sat sat_atom in
  match Sat.Model.find sat_atom sat_model with
  | Pos _ -> Pos smt_atom
  | Neg _ -> Neg smt_atom
```

So the SAT model:

```math
p_1 = \text{true}, \quad p_2 = \text{true}
```

gets converted back into:

```math
(6 \le a) \land (a < 0)
```

Now the theory solver gets involved.

For IDL, these constraints are normalized into difference constraints. The formula:

```math
6 \le a
```

can be rewritten as:

```math
0 - a \le -6
```

and:

```math
a < 0
```

can be rewritten as:

```math
a - 0 \le -1
```

So the IDL solver checks:

```math
(0 - a \le -6) \land (a - 0 \le -1)
```

These become graph edges:

```math
(a, 0, -6)
```

and:

```math
(0, a, -1)
```

As we saw in the IDL section, Bellman-Ford detects a negative cycle in this graph. A negative cycle means the system of difference constraints is impossible to satisfy.

So the theory solver returns:

```ocaml
Theory_unsat core
```

where the core is the theory-level reason for the contradiction:

```math
(6 \le a) \land (a < 0)
```

### Learning from a theory conflict

When the theory solver returns `Theory_unsat core`, Blue3 does not just stop immediately. Instead, it learns a new SAT clause from the theory conflict:

```ocaml
| Theory_unsat core ->
  let learned = theory_learn core conn in
  let sat_formula' = Sat.Formula.conjoin1 learned sat_formula in
  loop conn sat_formula'
```

The learning function is:

```ocaml
let theory_learn (Core core : 'k Theory.core) (conn : 'k t) : Sat.Formula.literal list =
  core
  |> List.map (fun lit -> abstract_literal lit conn)
  |> List.map Sat.Formula.negate
```

This takes the unsat core and negates every literal in it.

So if the theory conflict was:

```math
(6 \le a) \land (a < 0)
```

and the SAT abstraction was:

```text
p1 := (6 <= a)
p2 := (a < 0)
```

then the learned SAT clause is:

```math
\neg{p_1} \lor \neg{p_2}
```

This clause means:

> Do not allow the SAT solver to choose both `(6 <= a)` and `(a < 0)` at the same time again.

This is the SMT version of conflict-driven clause learning. The conflict was discovered by the theory solver, but the learned clause is added back to the SAT solver.

So the SAT formula changes from:

```math
p_1 \land p_2
```

to:

```math
p_1 \land p_2 \land (\neg{p_1} \lor \neg{p_2})
```

Now when CDCL runs again, it immediately sees that the boolean abstraction itself is impossible:

```math
p_1 = \text{true}
```

and:

```math
p_2 = \text{true}
```

are required by the first two clauses, but the learned clause says they cannot both be true.

So the SAT solver returns:

```ocaml
UNSAT
```

and then `cdcl_T` returns:

```ocaml
Solution.Unsat
```

This is the key idea behind SMT solving in Blue3:

> The SAT solver proposes a boolean assignment. The theory solver checks whether that assignment is meaningful. If it is not, the theory solver explains why, and Blue3 turns that explanation into a new SAT clause.

### Theory splitting

Sometimes the theory solver does not return `SAT` or `UNSAT`. Instead, it may need to split a theory literal into multiple possible cases.

This happens with integer disequality:

```math
x \ne y
```

IDL does not directly solve disequality as a primitive difference constraint. Instead, over integers:

```math
x \ne y
```

means:

```math
x < y
```

or:

```math
y < x
```

which can be rewritten as:

```math
x \le y - 1
```

or:

```math
y + 1 \le x
```

But as discussed earlier, Blue3 has to be careful not to globally assert the disequality unless the current SAT branch actually chose it.

So the split clause is guarded:

```math
(x = y) \lor (x \le y - 1) \lor (y + 1 \le x)
```

This means:

```math
x \ne y \implies (x \le y - 1) \lor (y + 1 \le x)
```

In the SMT loop, theory splits are handled here:

```ocaml
| Theory_split clauses ->
  let sat_formula' =
    List.fold_left
      (fun acc clause ->
        let sat_clause = abstract_clause clause conn in
        Sat.Formula.conjoin1 sat_clause acc)
      sat_formula
      clauses
  in
  loop conn sat_formula'
```

So if the theory solver returns new theory clauses, Blue3 abstracts those clauses into SAT clauses, conjoins them to the SAT formula, and restarts the loop.

This gives the SAT solver more structure to work with. Instead of treating:

```math
x \ne y
```

as a mysterious boolean atom, the SAT solver now knows that if equality is false, it must pick one of the concrete integer-ordering cases.

### The final Blue3 wrapper

The public-facing solver is `blue3`:

```ocaml
let blue3
  : type k. solver:k Theory.theory_solver -> k solver -> (bool, k) Formula.t -> k Solution.t =
  fun ~solver next formula ->
  let solve formula = cdcl_T ~solver formula in
  if contains_unsolvable formula then next formula
  else
    match formula with
    | Const_bool true -> Solution.Sat Model.empty
    | Const_bool false -> Solution.Unsat
    | _ ->
      match solve formula with
      | Solution.Unknown -> next formula
      | solution -> solution
```

This wraps the CDCL(T) loop with a few practical checks.

First, Blue3 checks whether the formula contains operations it does not currently know how to solve internally:

```ocaml
let contains_unsolvable formula =
  Formula.contains_binops [Times ; Divide ; Modulus ; Plus] formula
```

If the formula contains operations like multiplication, division, modulus, or general addition, Blue3 forwards it to the next solver:

```ocaml
if contains_unsolvable formula then next formula
```

This is because Blue3's internal theory solver is focused on IDL-style constraints, not full integer arithmetic.

Then it handles trivial boolean constants:

```ocaml
| Const_bool true -> Solution.Sat Model.empty
| Const_bool false -> Solution.Unsat
```

Otherwise, it calls the CDCL(T) solver:

```ocaml
match solve formula with
| Solution.Unknown -> next formula
| solution -> solution
```

So the final architecture is:

```text
Formula
  -> Blue3 simplifications / checks
  -> CDCL(T)
      -> SAT abstraction
      -> CDCL
      -> Theory solver
      -> theory conflict learning / splitting
  -> SAT / UNSAT / fallback
```

### Putting it all together

The SAT solver alone can only reason about boolean structure.

The IDL solver alone can only reason about conjunctions of difference constraints.

The SMT layer is what makes them useful together.

It lets Blue3 systematically solve "simple" formulas like:

```math
(a < 0) \land (6 \le a)
```

The SAT solver decides which theory atoms should be true or false. The theory solver checks whether those choices are consistent. When they are not, the theory solver explains the conflict, and CDCL learns from it.

That is the main idea behind Blue3's SMT solving strategy.
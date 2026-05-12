## Intro
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

The initial solution was an informal solver that would essentially guess values for our formulas. It certainly sped up solve times for some simple cases. But it had a design issue which was that it had to essentially match on every formula case we deemed "simple". As it turns out, telling a computer that a formula is "simple" programatically is a somewhat nontrivial task, even if it's easy for us to see as humans.

After some research, we found a specialized formula solver that could solve most of our "simple" cases called integer difference logic,
or just difference logic for short.

We'll begin by walking through our specific implementation of the difference logic solver *and* how it integrates with the "core" SAT solver and the "top-level" SMT solver. The hope is that by going over both the "domain-specific" difference logic solver and how it is used by the other 2 components, we will get a better understanding of Blue3's design.

### P = NP and the Boolean Satisfiability Problem
Paraphrasing (a lot), P = NP asks:

When we say "fast enough", we are being quite generous to the runtime. For example, we'd say the runtime is quadratic as "fast enough". Same with O(n^5), O(n^6), and so on. Just as long as the runtime is **polynomial**, then we can say it's fast enough.

Oversimplifying somewhat (a lot), `P` is the set of all problems that can be solved by a program fast enough. For example, ordering an array is in `P` because 

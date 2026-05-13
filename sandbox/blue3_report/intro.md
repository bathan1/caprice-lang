## Intro
Blue3 is a simple SMT solver implementation in OCaml. It was built to solve many of the simple SMT formulas that `ceval` outputs.

Before Blue3, [Z3](https://www.microsoft.com/en-us/research/project/z3-3/) was in charge of handling the SMT solving. It's still in charge of SMT solving, but now is used as a "fallback" for when Blue3 cannot solve the formula.

Z3 is more than capable of solving our formulas, of course, but the JHU Programming Language lab felt it was overkill for many of the cases. For instance, `ceval` might output something like:

```
(6 <= a) ^ (a < 0)
```

That formula is obviously UNSAT because `a` can't be `6` or more while also being less than `0`.

Many of the formulas `ceval` needs solved are simple / trivial like this. It's fast for Z3 to solve these formulas for sure, but our Z3 solver is the default general one. This results in Z3 performing a lot of extra processing that isn't necessary for our simple cases.

In other words, using Z3 to solve our simple formulas felt like using a bazooka to swat a fly.

Because of this along with the overhead of invoking the external Z3 C++ bindings from OCaml (since `caprice-lang` is written in OCaml), the team felt as if an in-house solver that can handle our trivial cases could improve the performance of `ceval` significantly. 

This report introduces Blue3, a minimal SMT solver for the caprice-lang. It may be small but has a full solve pipeline that uses modern techniques (the best it can, at least). We'll start by going over the theory solver we built to handle the "simple" cases programatically. From there, the rest of the report will follow its integration into the solve pipeline.


### P = NP and the Boolean Satisfiability Problem

Before going into Blue3, let's briefly talk about the P = NP problem. Oversimplifying, P = NP asks:

> If we can check a solution to some problem quickly, can we also solve the problem quickly?

For some problems, like multiplication, we can both *check* and *solve* fast enough. If you told me:

```
2 * 4 = 8
```

I can check your solution by just multiplying it out myself. Even if the numbers get large and filled with "not-nice" numbers, like:

```
123456789 * 123456789 = 1.52415788e16
```

I would still say I can solve this "quickly", because the amount of time to solve this scales **polynomially** with the size of the inputs, which is all that an algorithm needs to be considered "quick" for our purposes.

We say problems that can be solved quickly are in the class `P` of problems. Other problems in `P` include GPS routing and sorting a list. Informally speaking, you can think of these as the set of problems that are "easy" for a computer to solve, because the rate at which we've been CPUs have been speeding up makes even large degree polynomial runtimes "fast" for a computer, if not now, then in the future.

But some problems are harder than `P` for a computer to solve, like Sudoku. Given the Sudoku board:

+-------+-------+-------+
| 5 3 . | . 7 . | . . . |
| 6 . . | 1 9 5 | . . . |
| . 9 8 | . . . | . 6 . |
+-------+-------+-------+
| 8 . . | . 6 . | . . 3 |
| 4 . . | 8 . 3 | . . 1 |
| 7 . . | . 2 . | . . 6 |
+-------+-------+-------+
| . 6 . | . . . | 2 8 . |
| . . . | 4 1 9 | . . 5 |
| . . . | . 8 . | . 7 9 |
+-------+-------+-------+

Can we find a solution in any other way than brute force? Currently, we don't know of one, so it is "hard" for a computer to solve a problem like Sudoku.

What makes a problem like Sudoku interesting in math / computer science is that *given* a solution, like...

+-------+-------+-------+
| 5 3 4 | 6 7 8 | 9 1 2 |
| 6 7 2 | 1 9 5 | 3 4 8 |
| 1 9 8 | 3 4 2 | 5 6 7 |
+-------+-------+-------+
| 8 5 9 | 7 6 1 | 4 2 3 |
| 4 2 6 | 8 5 3 | 7 9 1 |
| 7 1 3 | 9 2 4 | 8 5 6 |
+-------+-------+-------+
| 9 6 1 | 5 3 7 | 2 8 4 |
| 2 8 7 | 4 1 9 | 6 3 5 |
| 3 4 5 | 2 8 6 | 1 7 9 |
+-------+-------+-------+

...we can check whether the solution is correct in time that scales with the number of rows and columns, so in *polynomial* time. Problems like these where it is "hard" to find a solution but "easy" to verify one are said to be in the `NP` class of problems.

This [amazing video](https://youtu.be/YX40hbAHx3s?si=SZDcUtKal7ur8Qw8) on P = NP explained what makes an NP problem `NP` the best. Paraphrasing somewhat:

> An `NP` problem is like a puzzle. *Checking* a puzzle solution is easy: just look at it. But *solving* a puzzle is hard because we don't have a better way than basically a brute force to solve a puzzle.

So Sudoku is like a puzzle, because we can "check" the solution by "just looking at it", but we can't programatically find the solution without essentially guessing and checking, at least as far as we know.

And then there are some harder problems that aren't in `NP`, like finding the best next move from a given chess board state:

    a  b  c  d  e  f  g  h
  +--+--+--+--+--+--+--+--+
8 |♖ |. |♗ |♕ |♔ |♗ |♘ |♖ |
  +--+--+--+--+--+--+--+--+
7 |♙ |♙ |♙ |. |. |♙ |♙ |♙ |
  +--+--+--+--+--+--+--+--+
6 |. |. |♘ |. |♙ |. |. |. |
  +--+--+--+--+--+--+--+--+
5 |. |. |. |♙ |. |. |. |. |
  +--+--+--+--+--+--+--+--+
4 |. |. |. |♟ |. |♝ |. |. |
  +--+--+--+--+--+--+--+--+
3 |. |. |♞ |. |. |♞ |. |. |
  +--+--+--+--+--+--+--+--+
2 |♟ |♟ |♟ |. |♟ |♟ |♟ |♟ |
  +--+--+--+--+--+--+--+--+
1 |♜ |. |. |♛ |♚ |♝ |. |♜ |
  +--+--+--+--+--+--+--+--+

If you told me that knight f6 is the next best move (for black):

    a  b  c  d  e  f  g  h
  +--+--+--+--+--+--+--+--+
8 |♖ |. |♗ |♕ |♔ |♗ |. |♖ |
  +--+--+--+--+--+--+--+--+
7 |♙ |♙ |♙ |. |. |♙ |♙ |♙ |
  +--+--+--+--+--+--+--+--+
6 |. |. |♘ |. |♙ |♘ |. |. |
  +--+--+--+--+--+--+--+--+
5 |. |. |. |♙ |. |. |. |. |
  +--+--+--+--+--+--+--+--+
4 |. |. |. |♟ |. |♝ |. |. |
  +--+--+--+--+--+--+--+--+
3 |. |. |♞ |. |. |♞ |. |. |
  +--+--+--+--+--+--+--+--+
2 |♟ |♟ |♟ |. |♟ |♟ |♟ |♟ |
  +--+--+--+--+--+--+--+--+
1 |♜ |. |. |♛ |♚ |♝ |. |♜ |
  +--+--+--+--+--+--+--+--+

You might be right, but I would have no way to verify that quickly, at least as far as we know.

Maybe for this specific early-game chess state, you could tell me if it is the best move in a reasonably fast amount of time, but the idea is that for an arbitrary board state, the best-next-move calculation doesn't scale polynomially with the number of turns. So you could say chess doesn't make for a great puzzle like Sudoku does, because unlike Sudoku where we can verify the solution by "just looking at it", we can't do the same with chess, at least, we don't think we can. Problems outside of NP don't pertain to the `P = NP` problem; I just wanted to illustrate one level "up" to contrast `NP` with other hard problems.

Returning back to `P` and `NP`, notice how if we can *solve* a problem in polynomial time, then we can always *verify* it in polynomial time. That is because we can run the same algorithm that solved the problem to check the solution. For example, if you gave me a shortest-distance-path for a graph you found using some polynomial graph search algorithm, then I could use the same graph search algorithm you used to check your solution. I don't have to necessarily use your algorithm, but the fact that I *can* is what matters.

So we can also interpret `P = NP` as asking whether the converse of that also holds:

> If we can *verify* a problem in polynomial time, then can we *solve* it in polynomial time?

You may have noticed my continuous assertion of the fact that we don't *know* of a quick solution to the NP problems, rather than asserting a quick solution does *not* exist. We are pretty sure that `P != NP`, at least I am, but we haven't been able to *prove* that the two sets are not equal, since it turns out that has proven difficult to do (clearly).

Paraphrasing the above video again, one of the reasons `P = NP` is an important question is because if we were somehow able to prove `P = NP`, then we have solved many real world problems like protein folding and a fast way to do prime factorization basically overnight. It would also mean a lot of the cryptographic functions we rely on for security would be cracked, because they all rely on the assumption that cracking them is NP hard.

In other words, the world would look a lot different if we were able to prove `P = NP`.

We say that many other problems would be solved as a consequence of solving `P = NP` because it was proven that [all problems in `NP` are reducible in polynomial time to `NP-Complete` problems]() by some very smart people. `NP-Complete` problems is the special subset of `NP` problems for which all problems in `NP` are reducible to in polynomial time. This means that if we can solve any `NP-complete` problem in polynomial time, then we have effectively shown that `P = NP`, because we can just reduce the `NP` problem into a problem we have shown to be solvable in polynomial time. There are many problems classified as `NP-Complete`, including the famous [21 seemingly unrelated problems]() that Richard Karp proved to be reducible from `3SAT`, the very first problem proven to be `NP-Complete`.

### 3SAT and Boolean Satisfiability

Oversimplifying again, `3SAT` asks:

> Given some conjunctive propositional formula where each conjuncted term is in the form `(p v q v r)` with at most **3** variables disjuncted, can we determine its **satisfiability** quickly?

The **satisfiability** property of a propositional **formula** tells you whether there exists we can find some set of variable assignments so that the formula evaluates out to true. If we can find at least one set of assignments, which we refer to as a **model**, that make the formula evaluate to `true`, then the formula is **satisfiable**. Otherwise, it is **unsatisfiable**.

For instance, the `3SAT` formula:

```
(p v q) ^ (~p v ~q)
```

is **satisfiable** because a valid model for the formula is:

```json
{
    "p": true,
    "q": false
}
```

How can we *verify* that this is the case? We just plug in the model values:

```
(true v true) ^ (~true v true) = 
```

and see that it spits out `true`:

```
true ^ (false v true) = true ^ true = true
```

But on the other hand, a trivial contradiction such as:

```
p ^ ~p
```

is **unsatisfiable**, because no matter what values we try for `p` (true or false), this will always come out to be false.

Given `n` variable assignments, the time it takes to plug them in scales linearly with `n`. So verifying that a solution to `3SAT` checks out is fast enough. Does a fast enough way to solve `3SAT` problems also exist?

If it were the case that `P = NP`, then the answer to would be yes, and you can probably ignore the rest of this paper...

But assuming it hasn't by the time of reading, then the short answer is "no". The longer answer is:

> "We don't know *if* a fast enough way to solve `3SAT` exists or not. We just don't *have* a fast way to solve `3SAT`... yet!"

`3SAT` is a specific version of the general `k-SAT` problem where `k` is the max (or exact, depending on your exact source) number of **literals**, or the disjuncted terms, allowed per **clause**, or the conjuncted term. `k-SAT` problems with `k >= 3` have also been shown to be `NP-complete` (based on the fact `3-SAT` is `NP-Complete`), and it makes up the foundation for the types of problems Blue3 solves, as at the lowest level of the Blue3 pipeline, it deals directly with propositional logic.

Blue3, and SMT solvers in general, solve "extended" formulas that are more expressive than pure propositional formulas which we'll call SMT formulas. Our original example is an SMT formula:

```
(6 <= a) ^ (a < 0)
```

Later down the solver pipeline, Blue3 eventually *maps* that SMT formula to a propositional form. It would map the above to:

```
p ^ q
```

- The first term `(6 <= a)` is asserting that `a` is greater than or equal to 6, so that maps to a binary true / false, which we can represent with the variable `p`.
- The second term `(a < 0)` is also asserting an inequality but is not logically connected to the first one, so that maps to a fresh variable, call that `q`.

### Useful Terminology

We'll conclude with a list of the common terminology that will be used throughout the rest of the report. This doesn't line up exactly with the formal terms from the literature, but they're distinguishing enough to work with for our purposes:

- A **Formula** is some boolean-returning expression that is either:
  1. A `SAT` formula, or a formula made entirely of propositional values and operators (like `p ^ q`)
  2. An `SMT` formula, or a formula made up of both propositional expressions *and* domain-specific expressions
     (like `6 <= a ^ a < 0 ^ (r v t)`. Note how we can include propositional formulas here if we wanted to...)
  While a **formula** technically refers to any arbitrary expression without regard to its structure, SMT solvers like Blue3 like to work with a special form called conjunctive normal form, or just CNF for short because it has some special properties that allows us to find for our solution in a practical amount of time, some of which we'll go into in the upcoming sections. So when we say "formula" here, we'll be referring specifically to CNF, unless stated otherwise.

- A formula in **CNF** has a structure that looks something like:
  ```
  (p v q v r) ^ (s v t v ~u)
  ```
  Where the "top" level operator is the boolean conjunctive `AND`, and the "anded" terms are *solely* disjunctive `OR`s.

- A **clause** is the disjunctive group that is "anded" with other **clauses** to compose the formula. So in the above example, the **clauses** are:
  ```
  (p v q v r)
  (s v t v ~u)
  ```

- A **literal** is the individual predicate / condition that is disjuncted (ORed) to form a clause and represents "unit" boolean values that make up the formula. It is either an atom or the negation of an atom. The **literals** from above are:
  ```
  p, q, r, s, t, ~u
  ```

- An **atom** is the canonical "base" expression a specific solver algorithm works with. The **atoms** from above are:
  ```
  p, q, r, s, t, u
  ```
  The distinction between a **literal** and an **atom** is somewhat subtle but important to handle when solving SMT formulas formally. An atom is the underlying base condition, while a literal is that atom as it appears in the formula: either positively as p or negatively as ~p. For example, a solver that works with equalities `=` may define:
  ```
  a = 1
  ```
  As an atom. It can either be instantiated in formulas "positively", as in, we are asserting that `a` equals `1`, or it can be instantied "negatively", as in, we are asserting that `a` does *not* equal `1`.

The formula / expression structure is probably the most important for Blue3. Everything below will also be reference throughout and is derived from the formula terminology as the foundation:

- A **Satisfiable** formula is one where we can find at least one satisfying set of assignments for.
- An **Unsatisfiable** formula is a formula where no such satisfying assignments exist.
- A **Solution** to a formula is either a map from free-variables to *concrete* values to indicate SAT *or* a literal `UNSAT` value that says otherwise.
- A **Model** of a **solution**
- A **solver** is a program that takes in some specific type of formula and returns a **solution**.

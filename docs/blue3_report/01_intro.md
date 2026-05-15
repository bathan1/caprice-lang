# Programming Blue3: An SMT solver for Caprice-Lang
Blue3 is a simple SMT solver implementation in OCaml. It was built to solve many of the simple SMT formulas that `ceval` outputs.

Before Blue3, [Z3](https://www.microsoft.com/en-us/research/project/z3-3/) was in charge of handling the SMT solving. It's still in charge of SMT solving, but now is used as a "fallback" for when Blue3 cannot solve the formula.

Z3 is more than capable of solving our formulas, of course, but the JHU Programming Language lab felt it was overkill for many of the cases. For instance, `ceval` might output something like:

```math
(6 \leq a) \land (a \lt 0)
```

That formula is obviously UNSAT because $a$ can't be $6$ or more while also being less than $0$.

Many of the formulas `ceval` needs solved are simple / trivial like this. It's fast for Z3 to solve these formulas for sure, but our Z3 solver is the default general one. This results in Z3 performing a lot of extra processing that isn't necessary for our simple cases.

In other words, using Z3 to solve our simple formulas felt like using a bazooka to swat a fly.

This with the overhead of invoking the external Z3 C++ bindings from OCaml (since `caprice-lang` is written in OCaml) made the team feel as if an in-house solver, one that can handle our trivial cases, could improve the performance of `ceval`. 

## Intro
This report introduces Blue3, a minimal SMT solver for the caprice-lang. It may be small but has a full solve pipeline that uses modern solver techniques. Our benchmarks showed that the Blue3 'frontend' Z3 was just over ~60% faster than Z3.

| avg_blue3 | avg_z3   |
|-----------|----------|
| 222.0μs   | 329.0μs  |

When Blue3 is given a formula it can't solve, it will pass the formula off to Z3, which is slower than just calling Z3 without Blue3. On average, it adds a cost of around 20.24μs:

| num_slow_cases | avg_slower_by | avg_percent_slower |
|----------------|---------------|--------------------|
| 38             | 20.24μs       | 4.59%              |

Which is about 5% slower than calling Z3 by itself. That's not a bad tradeoff for being able to solve the "simple" formulas 60% faster than Z3.

But before going into Blue3 and the benchmarks, let's talk a little about the $P = NP$ problem. 

### P = NP and the Boolean Satisfiability Problem

Oversimplifying, $P = NP$ asks:

> If we can check a solution to some problem quickly, can we also solve the problem quickly?

For some problems, like multiplication, we can both *check* and *solve* fast enough. If you told me:

```math
2 * 4 = 8
```

I can check your solution by just multiplying it out myself. Even if the numbers get large and filled with "not-nice" numbers, like:

```math
123456789 * 123456789 = 1.52415788e16
```

I would still say I can solve this "quickly", because the amount of time to solve this scales **polynomially** with the size of the inputs, which is all that an algorithm needs to be considered "quick" for our purposes.

We say problems that can be solved quickly are in the class $P$ of problems. Other problems in $P$ include GPS routing and sorting a list. Informally speaking, you can think of these as the set of problems that are "easy" for a computer to solve, because the rate at which we've been CPUs have been speeding up makes even large degree polynomial runtimes "fast" for a computer, if not now, then in the future.

But some problems are harder than $P$ for a computer to solve, like Sudoku. Given the Sudoku board:

```bash
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
```

Can we find a solution in any other way than brute force? Currently, we don't know of one, so it is "hard" for a computer to solve a problem like Sudoku.

What makes a problem like Sudoku interesting in math / computer science is that *given* a solution, like...

```bash
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
```

...we can check whether the solution is correct in time that scales with the number of rows and columns, so in *polynomial* time. Problems like these where it is "hard" to find a solution but "easy" to verify one are said to be in the $NP$ class of problems.

This [amazing video](https://youtu.be/YX40hbAHx3s?si=SZDcUtKal7ur8Qw8) on $P = NP$ explained what makes an $NP$ problem $NP$ the best. Paraphrasing the creator:

> $NP$ problems like puzzles. *Checking* a solution to a puzzle is easy: just look at it. But *solving* a puzzle is hard because we don't have a better way than basically a brute force to solve a puzzle.

So Sudoku is like a puzzle, because we can "check" the solution by "just looking at it", but we can't programatically find the solution without essentially guessing and checking, at least as far as we know.

And then there are some harder problems that aren't in $NP$, like finding the best next move from a given chess board state:

```bash
    a    b    c    d    e    f    g    h
  +----+----+----+----+----+----+----+-----+
8 | ♖ | .  | ♗  | ♕ | ♔ | ♗ | ♘  | ♖  |
  +----+----+----+----+----+----+----+-----+
7 | ♙ | ♙ | ♙  | .  | .  | ♙ | ♙  | ♙  |
  +----+----+----+----+----+----+----+-----+
6 | .  | .  | ♘ | .  | ♙  | .  | .  | .   |
  +----+----+----+----+----+----+----+-----+
5 | .  | .  | .  | ♙ | .  | .  | .  | .    |
  +----+----+----+----+----+----+----+-----+
4 | .  | .  | .  | ♟ | .  | ♝ | .  | .    |
  +----+----+----+----+----+----+----+-----+
3 | .  | .  | ♞ | .  | .  | ♞  | .  | .  |
  +----+----+----+----+----+----+----+-----+
2 | ♟ | ♟  | ♟ | .  | ♟ | ♟ | ♟  | ♟ |
  +----+----+----+----+----+----+----+-----+
1 | ♜  | .  | .  | ♛ | ♚ | ♝ | .  | ♜  |
  +----+----+----+----+----+----+----+-----+
```

If you told me that knight f6 is the next best move (for black):

```bash
    a    b    c    d    e    f    g    h
  +----+----+----+----+----+----+----+-----+
8 | ♖ | .  | ♗  | ♕ | ♔ | ♗ | .  | ♖  |
  +----+----+----+----+----+----+----+-----+
7 | ♙ | ♙ | ♙  | .  | .  | ♙ | ♙  | ♙  |
  +----+----+----+----+----+----+----+-----+
6 | .  | .  | ♘ | .  | ♙  | ♘  | .  | .   |
  +----+----+----+----+----+----+----+-----+
5 | .  | .  | .  | ♙ | .  | .  | .  | .    |
  +----+----+----+----+----+----+----+-----+
4 | .  | .  | .  | ♟ | .  | ♝ | .  | .    |
  +----+----+----+----+----+----+----+-----+
3 | .  | .  | ♞ | .  | .  | ♞  | .  | .  |
  +----+----+----+----+----+----+----+-----+
2 | ♟ | ♟  | ♟ | .  | ♟ | ♟ | ♟  | ♟ |
  +----+----+----+----+----+----+----+-----+
1 | ♜  | .  | .  | ♛ | ♚ | ♝ | .  | ♜  |
  +----+----+----+----+----+----+----+-----+
```

You might be right, but I would have no way to verify that quickly, at least as far as we know.

Maybe for this specific early-game chess state, you could tell me if it is the best move in a reasonably fast amount of time. But the idea is that for an arbitrary board state, the best-next-move calculation doesn't scale polynomially with the number of turns. 

So you could say chess doesn't make for a great puzzle like Sudoku does, because unlike Sudoku where we can verify the solution by "just looking at it", we can't do the same with chess, at least, we don't think we can. Problems outside of $NP$ don't pertain to the $P = NP$ problem; I just wanted to illustrate one level "up" to contrast $NP$ with other hard problems.

Returning to $P$ and $NP$, notice how if we can *solve* a problem in polynomial time, then we can always *verify* it in polynomial time. That is because we can run the same algorithm that solved the problem to check the solution. For example, if you gave me a shortest-distance-path for a graph you found using some polynomial graph search algorithm, then I could use the same graph search algorithm you used to check your solution. I don't have to necessarily use your algorithm, but the fact that I *can* is what matters.

So we can also interpret $P = NP$ as asking whether the converse of that also holds:

> If we can *verify* a problem in polynomial time, then can we *solve* it in polynomial time?

You may have noticed my continuous assertion of the fact that we don't *know* of a quick solution to the NP problems, rather than asserting a quick solution does *not* exist. We are pretty sure that $P \neq NP$, at least I am, but we haven't been able to *prove* that the two sets are not equal, since it turns out that has proven difficult to do (clearly).

Paraphrasing the above video again, one of the reasons $P = NP$ is an important question is because if we were somehow able to prove $P = NP$, then we have solved many real world problems like protein folding and a fast way to do prime factorization basically overnight. It would also mean a lot of the cryptographic functions we rely on for security would be cracked, because they all rely on the assumption that cracking them is NP hard.

In other words, the world would look a lot different if we were able to prove $P = NP$.

Many other problems would be solved as a consequence of solving $P = NP$ because it was proven that [all problems in $NP$ are reducible, ***in polynomial time***, to $\text{NP-complete}$ problems](https://dl.acm.org/doi/10.1145/800157.805047). $\text{NP-complete}$ problems are the special subset of $NP$ problems for which all problems in $NP$ are reducible to in polynomial time.

This means that if we can solve any $NP-complete$ problem in polynomial time, then we have effectively shown that $P = NP$, because we can just reduce the $NP$ problem into a problem we have shown to be solvable in polynomial time. There are many problems classified as $NP-Complete$, including the famous [21 seemingly unrelated problems](https://cgi.di.uoa.gr/~sgk/teaching/grad/handouts/karp.pdf) that Richard Karp proved to be reducible from 3SAT.

### 3SAT and Boolean Satisfiability

Oversimplifying again, 3SAT asks:

> Given some conjunctive propositional formula in CNF with at most **3** variables per clause, can we determine its **satisfiability** quickly?

The **satisfiability** property of a propositional **formula** tells you whether we can find some set of variable assignments so that the formula evaluates out to true. If we can find at least one set of assignments that makes the formula evaluate to `true`, then the formula is **satisfiable**. Otherwise, it is **unsatisfiable**.

For instance, the `3SAT` formula:

```math
(p \lor q) \land (\neg{p} \lor \neg{q})
```

is **satisfiable** because a valid model for the formula is:

```json
{
    "p": true,
    "q": false
}
```

How can we *verify* that this is the case? We just plug in the model values:

```math
(\text{true} \lor \text{false}) \land (\neg{\text{true}} \lor \neg{\text{false}}) = ?
```

and see that it spits out $\text{true}$.

But on the other hand, a contradiction, like the trivial one:

```math
p \land \neg{p} 
```

is **unsatisfiable**, because no matter what values we try for $p$ (true or false), this will always come out to be false.

Given $n$ variable assignments, the time it takes to plug them in scales linearly with $n$. So verifying that a solution to 3SAT checks out is fast enough. Does a fast enough way to solve 3SAT problems also exist?

If it were the case that $P = NP$, then the answer to would be yes, and you can probably ignore the rest of this paper...

But assuming it hasn't by the time of reading, then the short answer is "no". The longer answer is:

> "We don't know *if* a fast enough way to solve 3SAT exists or not. We just don't *have* a fast way to solve 3SAT... yet"

3SAT is a specific version of the general k-SAT problem where $k$ is the max (or exact, depending on your exact source) number of disjuncted terms per conjunct. k-SAT problems with $k >= 3$ have also been shown to be $\text{NP-complete}$ (based on the fact 3-SAT is $\text{NP-complete}$), and it makes up the foundation for the types of problems Blue3 solves, as at the lowest level of the Blue3 pipeline, it deals directly with propositional logic.

Blue3, and Satisfiability Modulo Theory (SMT) solvers in general, solve "extended" formulas that are more expressive than pure propositional formulas, which we'll call SMT formulas. Our original example is an SMT formula:

```math
(6 \leq a) \land (a \lt 0)
```

Later down the solver pipeline, Blue3 eventually *maps* that SMT formula to a propositional form. It would map the above to:

```math
p \land q
```

- The first term $(6 \leq a)$ asserts $a$ is greater than or equal to 6, so that maps to a binary true / false, which we can represent with the variable $p$.
- The second term $(a \lt 0)$ also asserts an inequality but is not logically connected to the first one, so that maps to a fresh variable, say $q$.

### Useful Terminology

We'll conclude with a list of the common terminology that will be used throughout the rest of the report. This doesn't line up exactly with the formal terms from the literature, but they're distinguishing enough to work with for our purposes:

#### Formula Terminology

- A **Formula** is some boolean-returning expression that. It has 3 specializations:

  - A $\text{SAT}$ formula, which we will refer to as a **propositional** formula so as to not confuse with the later solution terminology, is a formula made entirely of propositional values and operators (like $p \land q$)

  - An $\text{SMT}$ formula, or a formula made up of both propositional expressions *and* domain-specific expressions
     (like $(6 \leq a) \land (a \lt 0) \land (r \lor s)$. Note how we can include propositional formulas here if we wanted to...)

  - A $\text{Theory}$ formula, is the fragment of the original **SMT formula** that a particular $\text{Theory}$ solves. From:

    ```math
    (6 \leq a) \land (a \lt 0) \land (r \lor s)
    ```
  
    We have 2 $\text{Theory}$ formulas here, the $(6 \leq a) \land (a \lt 0)$ would have its interpretation covered by an `Ints` theory, while $(r \lor s)$ would be covered by a `Bools` theory.

    We typically won't be referring to these as $\text{Theory}$ formulas throughout because $\text{Theory}$ solvers (at least the ones we are concerned with) only ever work on conjunctions, so we will call the input to a theory solver as theory literals.

While a **formula** technically refers to any arbitrary expression without regard to its structure, SMT solvers like Blue3 like to work with a special form called conjunctive normal form, or CNF for short that simplifies many things.

So when we say "formula" here, we'll be referring specifically to an expression in CNF, unless stated otherwise.

- A **formula** in **CNF** has a structure that looks something like:
  ```math
  (p \lor q \lor r) \land (s \lor t \lor \neg{u})
  ```
  Where the "top" level operator is the boolean conjunctive $\land$ and the "anded" terms  made up *solely* by the disjunctions, also know as a...

- A **clause** is the disjunctive group that is "anded" with other **clauses** to compose the formula. In **CNF**, the only operator allowed is the logical or $\lor$. So in the above example, the **clauses** are:

  ```math
  (p \lor q \lor r)
  ```

  ```math
  (s \lor t \lor ~u)
  ```
  
  A **unit clause** is a clause with exactly 1 literal:

  ```math
  p \land q \land (r \lor s)
  ```
  
  Where $p$ and $q$ are unit clauses, but $r \lor s$ is not.

- A **literal** is the individual predicate / condition that is disjuncted (ORed) to form a clause and represents "unit" boolean values that make up the formula. It is either an atom or the negation of an atom. The **literals** from above are:

  ```math
  \text{Literals} = \set{p, q, r, s, t, \neg{u}}
  ```

- An **atom** is the canonical "base" expression a specific solver algorithm works with. The **atoms** from above are:
  ```math
  \text{Atoms} = \set{p, q, r, s, t, u}
  ```
  The distinction between a **literal** and an **atom** is somewhat subtle but important to understand when working with SMTs. An atom is the underlying base condition, while a literal is that atom as it appears in the formula: either positively as $p$ or negatively as $\neg{p}$.
  
  For example, a solver that works with equalities $=$ may parse this **literal**:

  ```math
  a = 1
  ```

  as the *positive* assertion of the **atom** $a = 1$, so in the positive case the **atom** looks identical to its **literal**. On the other hand, that same solver would:

  ```math
  a \neq 1
  ```
  
  as the *negative* assertion of the **atom** $a = 1$, *instead* of as its own **atom**.

#### Solver Terminology

- A **theory** is a set of domain-specific symbols attached with rules that define what combinations of symbols is valid and give those combinations meaning.

  - More formally, a theory $T$ is a set of first-order sentences over some signature $\Sigma$

- A **Satisfiable** formula, is one where we can find at least one satisfying set of assignments for.

- An **Unsatisfiable** is one that is not **satisfiable**, meaning a set of assignments that make the **formula** evaluate to $\text{true}$ is impossible.

- A **Solution** to a formula is either a map from free-variables to *concrete* values to indicate SAT *or* a literal $\text{UNSAT}$ value that says otherwise.

- A **Model** of a **solution**

- A **Solver** is a program that takes in some specific type of formula and returns a specific **solution**. Blue3 works with 3 types of solvers. In order of low to high level:

  - A $\text{SAT}$ **solver** finds the satisfiability of pure propositional **formulas**. For example, it knows how to work with formulas like:

    ```math
    p \land q
    ```
    
    But doesn't know how to interpret SMT **formulas** like:

    ```math
    (6 \leq a) \land (a \lt 0)
    ```

  - A $\text{Theory}$ **solver** finds the satisfiability of some of the formula's **clauses** or all of them in accordance with its **theory** rules.
  
    An SMT **formula** such as:

    ```math
    (6 \leq a) \land (a \lt 0)
    ```

    > While $\text{Theory}$ solvers don't *need* to work with conjunctions, they typically do, and for our purposes, they will always work with top-level conjunctions.

    Can be solved by a single Integer Arithmetic Theory solver alone, but a formula like:

    ```math
    (6 \leq a) \land (a \lt 0) \land (b \geq 4) \land (f(a) \neq f(b))
    ```
    
    cannot be solved by an Integer theory solver alone. We would need another theory solver to handle the $f(a) \neq f(b)$.

    It's often easier to implement theory solvers so that they only work with their own domain-specific formula fragments and leave building a final solution to...
    
  - An $\text{SMT}$ **solver** finds the satisfiability of a given **formula** by coordinating the results of an underlying $\text{SAT}$ solver with the appropriate $\text{Theory}$ solver(s). At a high level, it does so by:

    - *Decoding* the **SMT** formula into its corresponding **SAT** / propositional formula based on the **atoms** defined by its $\text{theory}$ solver(s). For example, the input **SMT** formula would be decoded like so in Blue3:

      ```math
      \text{decode}((6 \leq a) \land (a \lt 0)) = p \land q
      ```
      
      This is also known as *abstracting* the **SMT** formula.

    - *Solving* the decoded / abstracted propositional formula with the **SAT** solver:

      ```math
      \text{SAT\_solve}(p \land q)
      ```
      
      If $\text{SAT\_solve}$ were to return **UNSAT** for the propositional formula, then we can immediately return **UNSAT** as the answer because if the abstracted formula is **UNSAT**, then so is the original **SMT** formula.
      
      In our case, $\text{SAT\_solve}$ only sees $p \land q$, so it will return that this is **satisfiable**, because there are *3* satisfying assignments or **models** (either one of $p$ or $q$ is $\text{true}$ or both of them are). Our $\text{SAT\_solve}$ would return one such **model** to indicate $\text{SAT}$.
      
      Which of the satisfying propositional models the $\text{SAT\_solve}$ returns is ultimately up to the implementation, just as long as it is actually $\text{SAT}$.
      
    - Once the SAT solver returns a satisfying **model**, we then *encode* the propositional literals back to their **SMT** formula...

      ```math
      \text{encode}(p \land q) = (6 \leq a) \land (a \lt 0)
      ```
      
      And run our $\text{Theory}$ solver against the encoded **formula**:

      ```math
      \text{theory\_solve}(\text{Ints}, (6 \leq a) \land (a \lt 0))
      ```
      
      If it tells us **SAT**, then we return the concrete **model** the theory solver returned.

      In this case, however, the theory of $\text{Ints}$ to tells us this is **UNSAT**. In which case, we update the working **formula** state and rerun the above until we have exhausted all possible **SAT** combinations that returned by
      our calls to $\text{SAT\_solve}$.
      
Don't worry if you can't remember all of these terms. All you really need to takeaway from this that we have an explicit **CNF** hierarchy for our formulas:

1. **formula**: top level $\land$
2. **clause**: the $\land$-ed terms by the parent **formula**
3. **literal**: the $\lor$-ed terms by the parent **clause**
4. **atom**: the underlying identity of the literals

and that we have 3 types of formulas to work with:

1. **SAT** / boolean / propositional': $p \land q$
2. **Theory**: $(a <= 2) \land (b + a = 5)$
3. **SMT**: a conjunction of possible many **theory** formulas.
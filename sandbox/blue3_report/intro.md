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

Before going straight into our theory solver, let's briefly talk about the P = NP problem. Oversimplifying, P = NP asks:

> If we can make a program that can check a solution to some problem fast enough, can we also make a program that can solve the problem fast enough?

For some problems, like multiplication, we can both *check* and *solve* fast enough. If you told me:

```
2 * 4 = 8
```

I can check your solution by just multiplying it out myself. Even if the numbers get large and filled with "not-nice" numbers, like:

```
123456789 * 123456789 = 1.52415788e16
```

I would still say I can solve this "fast enough", because the amount of time to solve this scales **polynomially** with the size of the inputs.


When we can do that for a problem we say that it is in the class `P` of problems. Other problems in `P` include GPS routing and sorting a list. Informally speaking, you can think of these as the set of problems that are "easy" for a computer to solve, because the rate at which we've been CPUs have been speeding up makes even large degree polynomial runtimes "fast" for a computer, if not now, then in the future.

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

You might be right, but I would have no way to verify that, at least fast enough. That calculation is larger than polynomial as far as we know. So problems like chess are even "harder" than `NP`, and isn't of concern for the P = NP problem.

This [amazing video](https://youtu.be/YX40hbAHx3s?si=SZDcUtKal7ur8Qw8) on P = NP explained what makes an NP problem `NP` the best. Paraphrasing somewhat:

> An `NP` problem is like a puzzle. *Checking* a puzzle solution is easy: just look at it. But *solving* a puzzle is hard because we don't have a better way than basically a brute force to solve a puzzle.

Notice how if we can *solve* a problem in polynomial time, then we can also *verify* it in polynomial time because we could just run the algorithm that solved the problem fast enough to see if we get the same solution in a fast enough time. If you gave me a shortest-distance-path for a graph you found using some polynomial graph search algorithm, then I could use the same graph search algorithm you used to check your solution.

So to reframe the `P = NP` problem, we can also see it as asking:

> If we can *verify* a problem in polynomial time, then can we also *solve* it in polynomial time?

Even though it seems like `P != NP`, we haven't been able to prove that this is the case, which is why it remains an unsolved problem.

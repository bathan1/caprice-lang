## Benchmarks and Last Words
To finish this writeup, let's go over one instance of our benchmark script output.

Measurements were taken using the [Benchmark](https://ocaml.org/p/benchmark/1.7) library and compared the Blue3 solver with all of its ad-hoc rewrite heuristics + the cdcl loop against the Z3 solver by itself and used the 179 `f2.txt` formulas list outputted from a real run of the concolic evaluator.

The measurements below are averages across 100 trial runs, where each formula was solved 100 times by each solver, and then their average across those 100 runs were saved into the database. We recorded whether or not Z3 had to be called or not to determine which types of formulas Blue3 was able to solve by itself vs. which formulas had to be parsed by Blue3 just to send it to Z3 because it determined it can't solve it.

Here are the measurements.

### Measurements

#### What were the average runtimes from both solvers?

| avg_blue3 | avg_z3  |
|-----------|---------|
| 225.0μs   | 334.0μs |

On average, Blue3 was faster than calling Z3 directly on this benchmark set. This does not mean Blue3 is a better general-purpose SMT solver than Z3, but it does show that for the restricted formulas it was designed around, the extra simplification and CDCL(T)-style loop can pay off.

#### How many formulas were solved by Blue3 only?

| blue3_only_formula_count |
|--------------------------|
| 89                       |

Blue3 solved 89 of the 179 formulas without having to defer to Z3. This is the most important number for the project, because it shows that Blue3 was not just acting as a wrapper around Z3; it was actually able to solve a substantial portion of the concolic evaluator’s formulas on its own.

#### How many formulas had to be deferred to Z3?

| z3_deferred_formula_count |
|---------------------------|
| 90                        |

Blue3 deferred 90 formulas to Z3. This makes sense because Blue3 intentionally avoids formulas outside its current theory-solving scope, especially formulas involving operations like multiplication, division, and modulus. :contentReference[oaicite:3]{index=3}

#### On average, how much slower were the deferred cases than just calling Z3 by itself?

| num_deferred_cases | avg_slower_by | avg_percent_slower_than_z3 |
|--------------------|---------------|----------------------------|
| 90                 | -10.14μs      | -0.91%                     |

The deferred cases were not meaningfully slower than just calling Z3 directly. This suggests that Blue3’s initial parsing/checking overhead was small enough that even when it failed to solve a formula internally, it did not add a major penalty before handing the formula off.

#### How much faster were the fast cases on average?

| num_fast_cases | avg_faster_by | avg_percent_faster |
|----------------|---------------|--------------------|
| 136            | 148.85μs      | 65.42%             |

In the cases where Blue3 was faster, it was much faster on average. This is likely because many benchmark formulas had simple contradictions, redundant bounds, or IDL-style structure that Blue3’s lightweight simplification passes could exploit before needing a heavy general-purpose solver.

#### How much slower were the slow cases on average?

| num_slow_cases | avg_slower_by | avg_percent_slower |
|----------------|---------------|--------------------|
| 43             | 14.87μs       | 3.94%              |

When Blue3 was slower, it was only slightly slower on average. This is a good tradeoff for this prototype: the fast cases gained a lot, while the slow cases generally only lost a small amount

#### Top 10 fastest Blue3-only cases

| formula_id |            formula             | avg_time_us_blue3 | avg_time_us_z3 | avg_slower_by |
|------------|--------------------------------|-------------------|----------------|---------------|
| 9          | (0 < a) ^ ((a + 1) <= a)       | 0.1μs             | 90.78μs        | -90.68μs      |
| 8          | (0 < a) ^ ((a + 1) <= 1)       | 0.14μs            | 88.31μs        | -88.17μs      |
| 63         | (a < 0) ^ (0 < a)              | 0.28μs            | 113.9μs        | -113.62μs     |
| 56         | (not (a = 0)) ^ ((a + 10) = 0) | 0.28μs            | 256.38μs       | -256.1μs      |
| 88         | (0 < a) ^ (a < 1)              | 0.28μs            | 115.02μs       | -114.74μs     |
| 11         | (1 < a) ^ (a < 0)              | 0.29μs            | 111.89μs       | -111.6μs      |
| 159        | (a < 65) ^ (97 <= a)           | 0.29μs            | 127.14μs       | -126.85μs     |
| 64         | (0 < a) ^ (a < 0)              | 0.3μs             | 114.37μs       | -114.07μs     |
| 91         | (2 <= a) ^ (a <= 0)            | 0.3μs             | 122.11μs       | -121.81μs     |
| 10         | (1 < a) ^ (a <= 0)             | 0.31μs            | 105.69μs       | -105.38μs     |

The fastest Blue3-only cases are mostly simple contradictions or tight integer-bound formulas. These are exactly the kinds of formulas where a small custom solver can beat a general-purpose solver, because Blue3 can simplify them almost immediately instead of paying the cost of invoking a much larger solving pipeline.

#### Top 10 slowest Blue3-only cases

| formula_id |                           formula                            | avg_time_us_blue3 | avg_time_us_z3 | avg_slower_by |
|------------|--------------------------------------------------------------|-------------------|----------------|---------------|
| 168        | (48 <= a) ^ (not (a = 108)) ^ (not (a = 105)) ^ (not (a = 98... | 180.6μs           | 445.17μs       | -264.57μs     |
| 167        | (not (a = 108)) ^ (not (a = 105)) ^ (not (a = 98)) ^ ...      | 174.7μs           | 425.32μs       | -250.62μs     |
| 172        | (65 <= a) ^ (48 <= a) ^ (57 < a) ^ ...                       | 109.92μs          | 529.72μs       | -419.8μs      |
| 170        | (48 <= a) ^ (57 < a) ^ (not (a = 108)) ^ ...                 | 105.11μs          | 458.29μs       | -353.18μs     |
| 175        | (65 <= a) ^ (48 <= a) ^ (90 < a) ^ ...                       | 64.6μs            | 446.25μs       | -381.65μs     |
| 127        | (b <= a) ^ (0 <= a) ^ (0 <= b) ^ (not (b = a)) ^ (a <= b)    | 28.06μs           | 159.42μs       | -131.36μs     |
| 98         | (not (a = 0)) ^ (not (a = 1))                                | 18.66μs           | 192.11μs       | -173.45μs     |
| 72         | (not (a = 0)) ^ (not ((a - 1) = 0))                          | 17.53μs           | 211.74μs       | -194.21μs     |
| 125        | (b <= a) ^ (0 <= a) ^ (0 <= b) ^ (not (b = a))               | 14.14μs           | 281.65μs       | -267.51μs     |
| 85         | (0 <= a) ^ (not (a = 0)) ^ (not (a = 1))                     | 13.82μs           | 269.83μs       | -256.01μs     |

The slowest Blue3-only cases are still faster than Z3 in this benchmark, but they reveal where Blue3 does more work. Many of these formulas contain long lists of disequalities or redundant bounds, which means Blue3 has to spend more time simplifying, splitting, or pruning before it can conclude satisfiability or unsatisfiability.

#### What was the max time difference Blue3 beat Z3 by?

| max_diff |
|----------|
| 516.0μs  |

The largest win shows the upside of building a specialized solver for a narrow formula fragment. When the formula matches Blue3’s strengths, the difference is not just a small constant-factor improvement; it can be hundreds of microseconds faster on a single formula.

#### What was the max time difference Z3 beat Blue3 by?

| max_diff |
|----------|
| 98.0μs   |

The largest loss was much smaller than the largest win. This suggests that, at least on this benchmark set, Blue3’s downside risk was relatively limited compared to the potential speedup it got on formulas it could solve well.

#### What formulas did Z3 beat Blue3 on?

| formula_id |                           formula                            | time_us_blue3 | time_us_z3  |
|------------|--------------------------------------------------------------|---------------|-------------|
| 109        | (c <= (b % a)) ^ (c <= a) ^ (b <= ((b * a) / c)) ^ ...       | 1711.04908    | 1703.710556 |
| 107        | (not (a = 0)) ^ (c <= (b % a)) ^ (c <= a) ^ ...              | 1085.107327   | 1058.518887 |
| 103        | (0 < a) ^ (0 < b) ^ (0 < c) ^ ...                            | 970.878601    | 915.20071   |
| 105        | (0 < a) ^ (0 < b) ^ (0 < c) ^ ...                            | 916.521549    | 895.490646  |
| 99         | (0 < a) ^ (0 < b) ^ (not (a = 0)) ^ ...                      | 862.751007    | 854.830742  |

The formulas where Z3 beats Blue3 involve operations like modulus, multiplication, and division. This is expected because Blue3 is not trying to be a full arithmetic solver; once formulas leave the IDL-style fragment, Z3’s general-purpose machinery becomes the right tool.

### Last words

When I started this project, I honestly thought I was going to do the bare minimum. I initially signed up just so I can get away with not having to do 2 additional classes, so I went in with the expectation of fixing a few hundred or so lines of code and then move on. Instead, I found myself getting pulled deeper and deeper into SAT, SMT, and eventually the $P = NP$ problem.

$P = NP$ fascinated me because it gets at the core of what problem solving is. If checking a solution and finding a solution are secretly the same kind of task, then a huge part of what we call creativity, insight, or cleverness starts to look different...

Theoretical computer scientist Scott Aaronson once said:

> “If P=NP, then the world would be a profoundly different place than we usually assume it to be. There would be no special value in ‘creative leaps,’ no fundamental gap between solving a problem and recognizing the solution once it's found. Everyone who could appreciate a symphony would be Mozart; everyone who could follow a step-by-step argument would be Gauss; everyone who could recognize a good investment strategy would be Warren Buffett.”

For however long we don't know $P = NP$, you will always be able to make the case that there's something special about the way us humans approach our problems that a computer will never be able to fully replicate, like making a song that can be played hundreds of years after you go, or a video game that sells millions because it entertains millions, or even "feeling" when the right time and place to tell a funny is... 

It lets us continue hoping that our experiences and the emotions from them aren't deterministic chains of cause and effect fully explainable by a super smart computer. It leaves room for the possibility that there is something irreducible about the way we notice, create, and care about things. And I think that's pretty poetic, because there's nothing quite as human as just wanting to be someone special, even if just a little.

Blue3 obviously does not answer $P = NP$. It does not even come close. But building it showed me why these questions matter, and I hope it did for you as well.
### What were the average runtimes from both solvers?
| avg_blue3 | avg_z3  |
|-----------|---------|
| 292.0μs   | 304.0μs |
### Rows with the MIN times from both solvers
| trial_num | formula_id |                 formula                  | time_us_blue3 | time_us_z3 | which_min |
|-----------|------------|------------------------------------------|---------------|------------|-----------|
| 0         | 64         | (0 < a) ^ (a < 0)                        | 3.814697      | 112.056732 | blue3_min |
| 2         | 30         | (6 <= a) ^ (a < 0)                       | 3.814697      | 122.070312 | blue3_min |
| 3         | 36         | (2 < a) ^ (a < 0)                        | 3.814697      | 133.037567 | blue3_min |
| 3         | 89         | (1 <= a) ^ (0 < a) ^ (not ((a % 1) = 0)) | 113.010406    | 69.856644  | z3_min    |
| 4         | 30         | (6 <= a) ^ (a < 0)                       | 3.814697      | 111.103058 | blue3_min |
### Rows with the MAX times from both solvers
| trial_num | formula_id |                           formula                            | time_us_blue3 | time_us_z3  | which_min |
|-----------|------------|--------------------------------------------------------------|---------------|-------------|-----------|
| 0         | 108        | (c <= (b % a)) ^ (c <= a) ^ (0 < c) ^ (0 < a) ^ (0 < b) ^ (n | 8136.034012   | 3366.947174 | blue3_min |
|           |            | ot ((b % a) = 0)) ^ (not (c = 0)) ^ (not (a = 0)) ^ (((b * a |               |             |           |
|           |            | ) / c) < b)                                                  |               |             |           |
### How much faster were the fast cases on average?
| num_fast_cases | avg_faster_by | avg_percent_faster |
|----------------|---------------|--------------------|
| 345            | 110.83μs      | 49.6%              |
### How much slower were the slow cases on average?
| num_slow_cases | avg_slower_by | avg_percent_slower |
|----------------|---------------|--------------------|
| 548            | 50.25μs       | 9.81%              |
### What was the max time difference blue3 beat z3 by?
| max_diff |
|----------|
| 836.0μs  |
### What was the max time difference z3 beat blue3 by?
| max_diff |
|----------|
| 4769.0μs |

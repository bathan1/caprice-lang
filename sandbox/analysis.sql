.headers on
.mode markdown

.print "### What were the average runtimes from both solvers?"
SELECT 
    ROUND(AVG(time_us_blue3)) || 'μs' as avg_blue3,
    ROUND(AVG(time_us_z3)) || 'μs' as avg_z3
FROM benchmarks;

.print "### How many formulas were solved by blue3 only?"
SELECT COUNT(*) FROM benchmarks WHERE was_backend_used = 'false';

.print "### How many formulas had to be deferred to z3?"
SELECT COUNT(*) FROM benchmarks WHERE was_backend_used = 'true';

.print "### On average, how much slower were the deferred cases than just calling z3 by itself?"
SELECT
  COUNT(*) AS num_deferred_cases,
  ROUND(AVG(time_us_blue3 - time_us_z3), 2) || 'μs' AS avg_slower_by,
  ROUND(AVG(((time_us_blue3 - time_us_z3) * 100.0) / time_us_z3), 2) || '%' AS avg_percent_slower_than_z3
FROM benchmarks
WHERE was_backend_used = 'true';

.print "### Top 5 fastest deferred cases"
SELECT
  trial_num,
  formula_id,
  formula,
  ROUND(time_us_blue3, 2) || 'μs' AS time_us_blue3,
  ROUND(time_us_z3, 2) || 'μs' AS time_us_z3,
  ROUND(time_us_blue3 - time_us_z3, 2) || 'μs' AS slower_by
FROM benchmarks b
WHERE was_backend_used = 'true'
ORDER BY b.time_us_blue3 ASC
LIMIT 5;

.print "### Top 5 slowest deferred cases"
SELECT
  trial_num,
  formula_id,
  formula,
  ROUND(time_us_blue3, 2) || 'μs' AS time_us_blue3,
  ROUND(time_us_z3, 2) || 'μs' AS time_us_z3,
  ROUND(time_us_blue3 - time_us_z3, 2) || 'μs' AS slower_by
FROM benchmarks b
WHERE was_backend_used = 'true'
ORDER BY b.time_us_blue3 DESC
LIMIT 5;

.print "### Rows with the MIN times from both solvers"
WITH mins AS (
  SELECT
    MIN(time_us_blue3) AS min_blue3,
    MIN(time_us_z3) AS min_z3
  FROM benchmarks
)
SELECT DISTINCT
  b.trial_num,
  b.formula_id,
  b.formula,
  b.time_us_blue3,
  b.time_us_z3,
  CASE
    WHEN b.time_us_blue3 = m.min_blue3 THEN 'blue3_min'
    WHEN b.time_us_z3 = m.min_z3 THEN 'z3_min'
  END AS which_min
FROM benchmarks b
CROSS JOIN mins m
WHERE b.time_us_blue3 = m.min_blue3
   OR b.time_us_z3 = m.min_z3
ORDER BY b.trial_num, b.formula_id;

.print "### Rows with the MAX times from both solvers"
WITH maxs AS (
  SELECT
    MAX(time_us_blue3) AS max_blue3,
    MAX(time_us_z3) AS max_z3
  FROM benchmarks
)
SELECT DISTINCT
  b.trial_num,
  b.formula_id,
  b.formula,
  b.time_us_blue3,
  b.time_us_z3,
  CASE
    WHEN b.time_us_blue3 = m.max_blue3 THEN 'blue3_min'
    WHEN b.time_us_z3 = m.max_z3 THEN 'z3_min'
  END AS which_min
FROM benchmarks b
CROSS JOIN maxs m
WHERE b.time_us_blue3 = m.max_blue3
   OR b.time_us_z3 = m.max_z3
ORDER BY b.trial_num, b.formula_id;

.print "### How much faster were the fast cases on average?"

SELECT
  COUNT(*) AS num_fast_cases,
  ROUND(AVG(time_us_z3 - time_us_blue3), 2) || 'μs' AS avg_faster_by,
  ROUND(AVG(((time_us_z3 - time_us_blue3) * 100.0) / time_us_z3), 2) || '%' AS avg_percent_faster
FROM benchmarks
WHERE time_us_blue3 < time_us_z3;

.print "### How much slower were the slow cases on average?"

SELECT
  COUNT(*) AS num_slow_cases,
  ROUND(AVG(time_us_blue3 - time_us_z3), 2) || 'μs' AS avg_slower_by,
  ROUND(AVG(((time_us_blue3 - time_us_z3) * 100.0) / time_us_blue3), 2) || '%' AS avg_percent_slower
FROM benchmarks
WHERE time_us_blue3 > time_us_z3;

.print "### What was the max time difference blue3 beat z3 by?"
WITH diffs AS (
    SELECT time_us_z3 - time_us_blue3 as diff
    FROM benchmarks
)
SELECT 
    ROUND(MAX(diff)) || 'μs' as max_diff
FROM diffs;

.print "### What was the max time difference z3 beat blue3 by?"
WITH diffs AS (
    SELECT time_us_blue3 - time_us_z3 as diff
    FROM benchmarks
)
SELECT 
    ROUND(MAX(diff)) || 'μs' as max_diff
FROM diffs;

.print "### What were the slowest 5 cases solved entirely by blue3?"
SELECT DISTINCT
  b.trial_num,
  b.formula_id,
  b.formula,
  b.time_us_blue3,
  b.time_us_z3
FROM benchmarks b
WHERE was_backend_used = 'false'
ORDER BY time_us_blue3 DESC
LIMIT 5;

.print "### What formulas did z3 beat blue3 on?"
SELECT
  b.trial_num,
  b.formula_id,
  b.formula,
  b.time_us_blue3,
  b.time_us_z3
FROM benchmarks b
WHERE time_us_z3 < time_us_blue3
ORDER BY time_us_blue3 DESC
LIMIT 5;

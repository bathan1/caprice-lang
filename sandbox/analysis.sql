.read benchmark_results.sql
.headers on
.mode markdown

.print "### What were the average runtimes from both solvers?"
SELECT 
    ROUND(AVG(time_us_blue3)) || 'μs' as avg_blue3,
    ROUND(AVG(time_us_z3)) || 'μs' as avg_z3
FROM benchmark_results;

.print "### Rows with the MIN times from both solvers"
WITH mins AS (
  SELECT
    MIN(time_us_blue3) AS min_blue3,
    MIN(time_us_z3) AS min_z3
  FROM benchmark_results
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
FROM benchmark_results b
CROSS JOIN mins m
WHERE b.time_us_blue3 = m.min_blue3
   OR b.time_us_z3 = m.min_z3
ORDER BY b.trial_num, b.formula_id;

.print "### Rows with the MAX times from both solvers"
WITH maxs AS (
  SELECT
    MAX(time_us_blue3) AS max_blue3,
    MAX(time_us_z3) AS max_z3
  FROM benchmark_results
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
FROM benchmark_results b
CROSS JOIN maxs m
WHERE b.time_us_blue3 = m.max_blue3
   OR b.time_us_z3 = m.max_z3
ORDER BY b.trial_num, b.formula_id;

.print "### How much faster were the fast cases on average?"

SELECT
  COUNT(*) AS num_fast_cases,
  ROUND(AVG(time_us_z3 - time_us_blue3), 2) || 'μs' AS avg_faster_by,
  ROUND(AVG(((time_us_z3 - time_us_blue3) * 100.0) / time_us_z3), 2) || '%' AS avg_percent_faster
FROM benchmark_results
WHERE time_us_blue3 < time_us_z3;

.print "### How much slower were the slow cases on average?"

SELECT
  COUNT(*) AS num_slow_cases,
  ROUND(AVG(time_us_blue3 - time_us_z3), 2) || 'μs' AS avg_slower_by,
  ROUND(AVG(((time_us_blue3 - time_us_z3) * 100.0) / time_us_blue3), 2) || '%' AS avg_percent_slower
FROM benchmark_results
WHERE time_us_blue3 > time_us_z3;

.print "### What was the max time difference blue3 beat z3 by?"
WITH diffs AS (
    SELECT time_us_z3 - time_us_blue3 as diff
    FROM benchmark_results
)
SELECT 
    ROUND(MAX(diff)) || 'μs' as max_diff
FROM diffs;

.print "### What was the max time difference z3 beat blue3 by?"
WITH diffs AS (
    SELECT time_us_blue3 - time_us_z3 as diff
    FROM benchmark_results
)
SELECT 
    ROUND(MAX(diff)) || 'μs' as max_diff
FROM diffs;

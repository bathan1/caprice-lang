.headers on
.mode markdown

.print "### What were the average runtimes from both solvers?"
SELECT 
    ROUND(AVG(time_us_blue3)) || 'μs' as avg_blue3,
    ROUND(AVG(time_us_z3)) || 'μs' as avg_z3
FROM benchmarks;

.print "\n### How many formulas were solved by blue3 only?"
SELECT COUNT(DISTINCT formula_id) AS blue3_only_formula_count
FROM benchmarks
WHERE was_backend_used = 'false';

.print "\n### How many formulas had to be deferred to z3?"
SELECT COUNT(DISTINCT formula_id) AS z3_deferred_formula_count
FROM benchmarks
WHERE was_backend_used = 'true';

.print "\n### On average, how much slower were the deferred cases than just calling z3 by itself?"
SELECT
  COUNT(*) AS num_deferred_cases,
  ROUND(AVG(time_us_blue3 - time_us_z3), 2) || 'μs' AS avg_slower_by,
  ROUND(AVG(((time_us_blue3 - time_us_z3) * 100.0) / time_us_z3), 2) || '%' AS avg_percent_slower_than_z3
FROM benchmarks
WHERE was_backend_used = 'true';

.print "\n### How much faster were the fast cases on average?"

SELECT
  COUNT(*) AS num_fast_cases,
  ROUND(AVG(time_us_z3 - time_us_blue3), 2) || 'μs' AS avg_faster_by,
  ROUND(AVG(((time_us_z3 - time_us_blue3) * 100.0) / time_us_z3), 2) || '%' AS avg_percent_faster
FROM benchmarks
WHERE time_us_blue3 < time_us_z3;

.print "\n### How much slower were the slow cases on average?"

SELECT
  COUNT(*) AS num_slow_cases,
  ROUND(AVG(time_us_blue3 - time_us_z3), 2) || 'μs' AS avg_slower_by,
  ROUND(AVG(((time_us_blue3 - time_us_z3) * 100.0) / time_us_blue3), 2) || '%' AS avg_percent_slower
FROM benchmarks
WHERE time_us_blue3 > time_us_z3;

.print "\n### Top 10 fastest blue3-only cases"

SELECT
  formula_id,
  formula,
  COUNT(*) AS runs,
  ROUND(AVG(time_us_blue3), 2) || 'μs' AS avg_time_us_blue3,
  ROUND(AVG(time_us_z3), 2) || 'μs' AS avg_time_us_z3,
  ROUND(AVG(time_us_blue3) - AVG(time_us_z3), 2) || 'μs' AS avg_slower_by
FROM benchmarks
WHERE was_backend_used = 'false'
GROUP BY formula_id, formula
ORDER BY AVG(time_us_blue3) ASC
LIMIT 10;

.print "\n### Top 10 slowest blue3-only cases"

SELECT
  formula_id,
  formula,
  COUNT(*) AS runs,
  ROUND(AVG(time_us_blue3), 2) || 'μs' AS avg_time_us_blue3,
  ROUND(AVG(time_us_z3), 2) || 'μs' AS avg_time_us_z3,
  ROUND(AVG(time_us_blue3) - AVG(time_us_z3), 2) || 'μs' AS avg_slower_by
FROM benchmarks
WHERE was_backend_used = 'false'
GROUP BY formula_id, formula
ORDER BY AVG(time_us_blue3) DESC
LIMIT 10;

.print "\n### What was the max time difference blue3 beat z3 by?"
WITH diffs AS (
    SELECT time_us_z3 - time_us_blue3 as diff
    FROM benchmarks
)
SELECT 
    ROUND(MAX(diff)) || 'μs' as max_diff
FROM diffs;

.print "\n### What was the max time difference z3 beat blue3 by?"
WITH diffs AS (
    SELECT time_us_blue3 - time_us_z3 as diff
    FROM benchmarks
)
SELECT 
    ROUND(MAX(diff)) || 'μs' as max_diff
FROM diffs;

.print "### What formulas did z3 beat blue3 on?"
SELECT
  b.formula_id,
  b.formula,
  b.time_us_blue3,
  b.time_us_z3
FROM benchmarks b
WHERE time_us_z3 < time_us_blue3
ORDER BY time_us_blue3 DESC
LIMIT 5;

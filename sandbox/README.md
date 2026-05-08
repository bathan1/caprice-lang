# Sandbox

## One shot analysis markdown
```bash
{
  cat f2.txt | dune exec ./main.exe -- 1>/dev/null 2> >(tail -n +3)
  cat analysis.sql
} | sqlite3 ":memory:" > analysis.out
```

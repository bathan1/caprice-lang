
## One shot analysis markdown
```bash
{
  cat f2.txt | dune exec ./main.exe
  cat analysis.sql
} | sqlite3 ":memory:" > analysis.out
```

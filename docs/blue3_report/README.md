## One shot generate pdf:

pandoc programming_blue3.md \
  --from=markdown+tex_math_dollars \
  --pdf-engine=xelatex \
  -H unicode-fixes.tex \
  -V monofont="DejaVu Sans Mono" \
  -o programming_blue3.pdf

.PHONY: test
test:
	dune exec src-test/main.exe --no-buffer --force -- -e -q
test-slow:
	dune exec src-test/main.exe --no-buffer --force -- -e
clean:
	dune clean
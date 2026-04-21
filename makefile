TD ?= ./test/
export CTL_TESTDIR := $(TD)

RUN = dune exec src-test/main.exe --no-buffer --force --

.PHONY: test test-slow clean
test:
	$(RUN) -e -q
test-slow:
	$(RUN) -e
clean:
	dune clean
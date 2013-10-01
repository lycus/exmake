INSTALL ?= install
MIX ?= mix
DIALYZER ?= dialyzer

PREFIX ?= /usr/local

.PHONY: all escript ebin clean test dialyze install uninstall

all: ebin/exmake

escript: ebin/exmake

ebin/exmake: ebin/exmake.app
	@$(MIX) escriptize

ebin: ebin/exmake.app

ebin/exmake.app: $(wildcard lib/*.ex) $(wildcard lib/lib/*.ex)
	@$(MIX) compile

clean:
	@$(MIX) clean
	@$(RM) -r tmp

test:
	@$(MIX) test --trace

dialyze: ebin/exmake.app
	$(DIALYZER) --no_check_plt -r ebin \
		-Wunmatched_returns \
		-Werror_handling

install: ebin/exmake
	$(INSTALL) -m755 -d $(PREFIX)
	$(INSTALL) -m755 -d $(PREFIX)/bin
	$(INSTALL) -m755 ebin/exmake $(PREFIX)/bin
	$(INSTALL) -m755 -d $(PREFIX)/lib
	$(INSTALL) -m755 -d $(PREFIX)/lib/exmake

uninstall:
	$(RM) $(PREFIX)/bin/exmake

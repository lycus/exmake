INSTALL ?= install
MIX ?= mix
DIALYZER ?= dialyzer

PREFIX ?= /usr/local

override _build = _build/shared/lib/exmake/ebin

.PHONY: all escript ebin clean test dialyze install uninstall

all: $(_build)/exmake

escript: $(_build)/exmake

$(_build)/exmake: $(_build)/exmake.app
	@$(MIX) escript.build

ebin: $(_build)/exmake.app

$(_build)/exmake.app: $(wildcard lib/*.ex) $(wildcard lib/lib/*.ex)
	@$(MIX) compile

clean:
	@$(MIX) clean
	@$(RM) -r tmp

test:
	@$(MIX) test --trace

dialyze: $(_build)/exmake.app
	$(DIALYZER) --no_check_plt -r $(_build) \
		-Wunmatched_returns \
		-Werror_handling

install: $(_build)/exmake
	$(INSTALL) -m755 -d $(PREFIX)
	$(INSTALL) -m755 -d $(PREFIX)/bin
	$(INSTALL) -m755 $(_build)/exmake $(PREFIX)/bin
	$(INSTALL) -m755 -d $(PREFIX)/lib
	$(INSTALL) -m755 -d $(PREFIX)/lib/exmake

uninstall:
	$(RM) $(PREFIX)/bin/exmake

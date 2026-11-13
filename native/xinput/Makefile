# Builds the binding against the scripted XInput in tests/fake_loader.c and
# runs its spec, so the Lua-facing half is tested where Windows cannot run.
# The real DLL is build.cmd's, on Windows.
#
#   make -C native/xinput test

CC ?= gcc
CFLAGS ?= -O0 -g -std=c99 -Wall -Wextra -Werror -fPIC
BUSTED ?= busted

BUILD := build/test
SOURCES := src/luaxinput.c tests/fake_loader.c
HEADERS := src/xinput_abi.h src/loader.h

$(BUILD)/_LuaXInput.so: $(SOURCES) $(HEADERS)
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -Iinclude -Isrc -shared -o $@ $(SOURCES)

test: $(BUILD)/_LuaXInput.so
	$(BUSTED) tests/luaxinput_spec.lua

clean:
	rm -rf build

.PHONY: test clean

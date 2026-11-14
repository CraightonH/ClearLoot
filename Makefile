LUA ?= lua
PYTHON ?= python3

.PHONY: test package
test:
	$(LUA) tests/model.lua
	$(LUA) tests/history.lua
	$(LUA) tests/betting.lua
	$(LUA) tests/integration.lua

package:
	$(PYTHON) scripts/package.py

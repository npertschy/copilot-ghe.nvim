.PHONY: test test_file format

CODECOMPANION_PATH ?= $(HOME)/.local/share/nvim/lazy/codecompanion.nvim

test:
	@echo Testing...
	LC_ALL=C nvim --headless --noplugin -u ./scripts/minimal_init.lua \
		-c "lua MiniTest.run()" 2>&1

test_file:
	@echo Testing file $(FILE)...
	LC_ALL=C nvim --headless --noplugin -u ./scripts/minimal_init.lua \
		-c "lua MiniTest.run_file('$(FILE)')" 2>&1

format:
	@echo Formatting...
	stylua lua/ tests/ -f $(CODECOMPANION_PATH)/stylua.toml

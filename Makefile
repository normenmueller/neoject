# -----------------------------------------------------------------------------
# Makefile for installing neoject
# -----------------------------------------------------------------------------

INSTALL_DIR := $(HOME)/.local/bin
SCRIPT_SRC  := ./src/neoject.sh
SCRIPT_DEST := $(INSTALL_DIR)/neoject

.PHONY: all install uninstall

all: install

install:
	@echo "🔧 Installing 🧬neoject → $(SCRIPT_DEST)"
	@mkdir -p $(INSTALL_DIR)
	@cp $(SCRIPT_SRC) $(SCRIPT_DEST)
	@chmod +x $(SCRIPT_DEST)
	@echo "✅ Installed neoject"
	@which neoject || echo "ℹ️  Not found in current shell. Try restarting or reloading your shell config."
	@echo ""
	@if ! echo "$$PATH" | grep -q "$$HOME/.local/bin" ; then \
		echo "⚠️  Warning: $(INSTALL_DIR) is not in your PATH."; \
		echo "   Add this to your shell config (e.g. ~/.bashrc or ~/.zshrc):"; \
		echo "   export PATH=\"\$$HOME/.local/bin:\$$PATH\""; \
	fi

uninstall:
	@echo "🗑️  Uninstalling neoject from $(SCRIPT_DEST)"
	@rm -f $(SCRIPT_DEST)
	@echo "✅ Uninstalled."


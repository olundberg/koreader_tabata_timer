PLUGIN_NAME = tabatatimer.koplugin
PLUGINS_DIR = ../koreader/plugins

.PHONY: link clean test emulator

# Skapar länk för emulatorn (eftersom tabata.csv ligger i mappen följer den med automatiskt genom länken!)
emulator: test
	@mkdir -p $(PLUGINS_DIR)
	@if [ -e $(PLUGINS_DIR)/$(PLUGIN_NAME) ]; then \
		rm -rf $(PLUGINS_DIR)/$(PLUGIN_NAME); \
	fi
	ln -s ../../koreader_tabata_timer $(PLUGINS_DIR)/$(PLUGIN_NAME)
	@echo "Länk skapad! Plugin och CSV är redo i emulatorn."

clean:
	rm -rf $(PLUGINS_DIR)/$(PLUGIN_NAME)
	@echo "Länk borttagen."

test:
	lua tests/test_parser.lua

PLUGIN_ID := liambryant.todo
PLUGINS_DIR := $(HOME)/.config/omarchy/plugins
TARGET := $(PLUGINS_DIR)/$(PLUGIN_ID)
SOURCES := manifest.json Todo.qml BarWidget.qml TodoDoc.js scan.sh

.PHONY: test validate install link uninstall reload

test:
	node test/tododoc.test.js
	bash test/scan.test.sh

validate:
	omarchy plugin validate .

install: validate
	mkdir -p $(TARGET)
	cp $(SOURCES) $(TARGET)/
	chmod +x $(TARGET)/scan.sh
	omarchy-shell -q shell rescanPlugins || true
	@echo "installed to $(TARGET)"

# Edit in place: the shell hot-reloads anything under the plugins directory.
link:
	@test ! -e $(TARGET) || test -L $(TARGET) || \
	  { echo "$(TARGET) exists and is not a symlink; run 'make uninstall' first"; exit 1; }
	rm -f $(TARGET)
	mkdir -p $(PLUGINS_DIR)
	ln -s $(CURDIR) $(TARGET)
	omarchy-shell -q shell rescanPlugins || true
	@echo "linked $(TARGET) -> $(CURDIR)"

uninstall:
	rm -rf $(TARGET)
	omarchy-shell -q shell rescanPlugins || true

reload:
	omarchy-shell shell rescanPlugins

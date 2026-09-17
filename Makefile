SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

PLUGIN_ID := liambryant.todo
PLUGINS_DIR ?= $(HOME)/.config/omarchy/plugins
TARGET := $(PLUGINS_DIR)/$(PLUGIN_ID)
RELOAD ?= 1
SOURCES := manifest.json $(wildcard *.qml *.js *.sh *.py)
VERSION = $(shell python3 -c 'import json; print(json.load(open("manifest.json"))["version"])')
DIST_NAME = super-t-$(VERSION)
DIST_FILES := $(SOURCES) Makefile README.md CONTRIBUTING.md CHANGELOG.md LICENSE docs test scripts .github .gitignore

.PHONY: test test-qml test-dist lint validate-source validate install link uninstall reload dist

test:
	@for test in test/*.test.js; do node "$$test" || exit; done
	bash test/parser-parity.test.sh
	bash test/scan.test.sh
	bash test/newlist.test.sh
	python3 -B -m unittest discover -s test -p 'backend*.py'
	python3 -B -m unittest discover -s test -p 'wayland*_test.py'

test-qml:
	bash test/qml-smoke.sh

lint:
	@for script in *.sh test/*.sh; do bash -n "$$script"; done
	shellcheck *.sh test/*.sh

validate-source:
	python3 -B scripts/validate.py
	@python3 -B -c 'import service'

validate: validate-source
	omarchy plugin validate .
	@python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else "Python 3.10 or newer is required")'

install: validate
	mkdir -p "$(TARGET)"
	cp $(SOURCES) "$(TARGET)/"
	chmod +x "$(TARGET)/scan.sh" "$(TARGET)/newlist.sh"
	@if [ "$(RELOAD)" = 1 ]; then omarchy-shell -q shell rescanPlugins || true; fi
	@echo "installed to $(TARGET)"

link:
	@test ! -e "$(TARGET)" || test -L "$(TARGET)" || \
	  { echo "$(TARGET) exists and is not a symlink; run 'make uninstall' first"; exit 1; }
	rm -f "$(TARGET)"
	mkdir -p "$(PLUGINS_DIR)"
	ln -s "$(CURDIR)" "$(TARGET)"
	@if [ "$(RELOAD)" = 1 ]; then omarchy-shell -q shell rescanPlugins || true; fi
	@echo "linked $(TARGET) -> $(CURDIR)"

uninstall:
	rm -rf "$(TARGET)"
	@if [ "$(RELOAD)" = 1 ]; then omarchy-shell -q shell rescanPlugins || true; fi

reload:
	omarchy-shell shell rescanPlugins

test-dist: dist
	python3 -B -m unittest discover -s test -p 'distribution_test.py'

dist: validate-source
	mkdir -p dist
	tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner \
	  --exclude='__pycache__' --exclude='*.pyc' --exclude='*.pyo' \
	  --mode='u+rwX,go+rX,go-w' --transform='s,^,$(DIST_NAME)/,' -cf - $(DIST_FILES) \
	  | gzip -n > "dist/$(DIST_NAME).tar.gz"
	cd dist && sha256sum "$(DIST_NAME).tar.gz" > "$(DIST_NAME).tar.gz.sha256"

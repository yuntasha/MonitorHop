APP        := build/MonitorHop.app
INSTALL_DIR ?= /Applications
BUNDLE_ID  := com.alencup.MonitorHop

.PHONY: all build test app icon install uninstall run stop check reset-permission clean

all: app

build:            ## Debug build of all targets
	swift build

test:             ## Unit tests (Swift Testing)
	swift test

app:              ## Release build + build/MonitorHop.app
	./scripts/build-app.sh

icon:             ## Regenerate Resources/AppIcon.icns
	./scripts/make-icon.sh

install: app stop ## Copy the app to /Applications and start it
	rm -rf "$(INSTALL_DIR)/MonitorHop.app"
	cp -R "$(APP)" "$(INSTALL_DIR)/"
	open "$(INSTALL_DIR)/MonitorHop.app"

uninstall: stop   ## Remove the app, its settings and its permission entry
	-tccutil reset Accessibility $(BUNDLE_ID) || echo "warning: remove MonitorHop manually in System Settings › Privacy & Security › Accessibility"
	-defaults delete $(BUNDLE_ID)
	rm -rf "$(INSTALL_DIR)/MonitorHop.app"
	rm -rf "$(HOME)/Library/Application Support/MonitorHop"

run: app stop     ## Run the freshly built app from build/
	open "$(APP)"

stop:             ## Quit a running MonitorHop
	-pkill -x MonitorHop; sleep 0.5

check: app        ## Print diagnostics (permissions, monitors, hotkeys)
	"$(APP)/Contents/MacOS/MonitorHop" --check

reset-permission: ## Forget the Accessibility grant (needed after rebuilding an ad-hoc signed app)
	tccutil reset Accessibility $(BUNDLE_ID)

clean:
	rm -rf .build build

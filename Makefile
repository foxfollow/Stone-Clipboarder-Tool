# Local shortcuts. CI builds with .github/workflows/release.yml, not this.
# Details and the data each build uses: scripts/local-build.sh

PROJECT := StoneClipboarderTool.xcodeproj
SCHEME  := StoneClipboarderTool
XCB     := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination "platform=macOS"

.PHONY: help build test release run install path clean

help:
	@echo "make build    Debug compile check"
	@echo "make test     unit tests"
	@echo "make release  Release build (Xcode signing) into DerivedData/…/Build/Products/Release"
	@echo "make run      release, quit the running app, open the built one"
	@echo "make install  CI-style ad-hoc build into /Applications (INSTALL_DIR=…), then open it"
	@echo "make path     print the DerivedData Release .app path"
	@echo "make clean    remove build/ (install's DerivedData) and clean the Release build"

build:
	$(XCB) -configuration Debug build -quiet

test:
	$(XCB) test -quiet

release run install path:
	@scripts/local-build.sh $@

clean:
	rm -rf build
	$(XCB) -configuration Release clean -quiet

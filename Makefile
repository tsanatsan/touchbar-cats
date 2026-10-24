APP := build/TouchBar Cats.app
ARCH ?= arm64

.PHONY: build run install release clean

build:
	ARCH=$(ARCH) ./build-local.sh

run: build
	-pkill -x MTMR
	open "$(APP)"

install: build
	-pkill -x MTMR
	rm -rf "/Applications/TouchBar Cats.app"
	cp -R "$(APP)" /Applications/
	open "/Applications/TouchBar Cats.app"

# zip for GitHub Releases: universal app, ready to drag into Applications
release:
	ARCH=universal ./build-local.sh
	cd build && ditto -c -k --keepParent "TouchBar Cats.app" TouchBar-Cats.zip

clean:
	rm -rf build

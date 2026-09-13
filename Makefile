SCHEME := LookOff
CONFIG ?= Release
DERIVED := build
APP := $(DERIVED)/Build/Products/$(CONFIG)/LookOff.app

.PHONY: build debug run install open clean

build:
	xcodebuild -project LookOff.xcodeproj -scheme $(SCHEME) -configuration $(CONFIG) -derivedDataPath $(DERIVED) CODE_SIGN_IDENTITY="-" AD_HOC_CODE_SIGNING_ALLOWED=YES

debug:
	$(MAKE) build CONFIG=Debug

run: build
	open "$(APP)"

install: build
	rm -rf /Applications/LookOff.app
	cp -R "$(APP)" /Applications/LookOff.app
	xattr -cr /Applications/LookOff.app
	open /Applications/LookOff.app

open:
	open LookOff.xcodeproj

clean:
	rm -rf "$(DERIVED)"

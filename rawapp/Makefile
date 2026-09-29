# Builds GPSBag.app (the zero-interaction raw readout) for armv7 / iOS 8.0
# on the build Mac. Same toolchain story as ../app/Makefile; geodesy comes
# from ../shared.
SDK        := $(HOME)/ios/sdks/iPhoneOS9.3.sdk
TARGET     := -target armv7-apple-ios8.0
WARN       := -Wall -Wextra
CFLAGS     := $(TARGET) -isysroot $(SDK) -O2 $(WARN) -I../shared
OBJCFLAGS  := $(CFLAGS) -fobjc-arc
FRAMEWORKS := -framework UIKit -framework CoreLocation -framework Foundation \
              -framework CoreGraphics

APP   := build/GPSBag.app
SRC_M := $(wildcard src/*.m)
SRC_C := $(wildcard ../shared/*.c)
OBJ   := $(SRC_M:src/%.m=build/obj/%.o) \
         $(patsubst %.c,build/obj/%.o,$(notdir $(SRC_C)))

all: $(APP)/GPSBag $(APP)/Info.plist $(APP)/Icon-60@2x.png

$(APP)/Icon-60@2x.png: Resources/Icon-60@2x.png | $(APP)
	cp $< $@

build/obj/%.o: src/%.m src/*.h | build/obj
	clang $(OBJCFLAGS) -c $< -o $@

build/obj/%.o: ../shared/%.c ../shared/%.h | build/obj
	clang $(CFLAGS) -c $< -o $@

$(APP)/GPSBag: $(OBJ) | $(APP)
	clang $(TARGET) -isysroot $(SDK) $(OBJ) $(FRAMEWORKS) -o $@

$(APP)/Info.plist: Resources/Info.plist | $(APP)
	cp $< $@

build/obj $(APP):
	mkdir -p $@

# The geodesy tests live in ../app; nothing app-specific to test here.
test:
	@true

clean:
	rm -rf build

.PHONY: all clean test

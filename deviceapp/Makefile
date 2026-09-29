# Builds DeviceBag.app (sensor/diagnostics readout) for armv7 / iOS 8.0 on
# the build Mac. Same toolchain story as ../app/Makefile.
SDK        := $(HOME)/ios/sdks/iPhoneOS9.3.sdk
TARGET     := -target armv7-apple-ios8.0
WARN       := -Wall -Wextra
CFLAGS     := $(TARGET) -isysroot $(SDK) -O2 $(WARN)
OBJCFLAGS  := $(CFLAGS) -fobjc-arc
FRAMEWORKS := -framework UIKit -framework CoreLocation -framework CoreMotion \
              -framework Foundation -framework CoreGraphics

APP   := build/DeviceBag.app
SRC_M := $(wildcard src/*.m)
SRC_C := $(wildcard src/*.c)
OBJ   := $(SRC_M:src/%.m=build/obj/%.o) $(SRC_C:src/%.c=build/obj/%.o)

all: $(APP)/DeviceBag $(APP)/Info.plist $(APP)/Icon-60@2x.png

$(APP)/Icon-60@2x.png: Resources/Icon-60@2x.png | $(APP)
	cp $< $@

build/obj/%.o: src/%.m src/*.h | build/obj
	clang $(OBJCFLAGS) -c $< -o $@

build/obj/%.o: src/%.c src/*.h | build/obj
	clang $(CFLAGS) -c $< -o $@

$(APP)/DeviceBag: $(OBJ) | $(APP)
	clang $(TARGET) -isysroot $(SDK) $(OBJ) $(FRAMEWORKS) -o $@

$(APP)/Info.plist: Resources/Info.plist | $(APP)
	cp $< $@

build/obj $(APP):
	mkdir -p $@

# Device-side sensor probe (run over SSH; see probe/probe.c).
probe: | build
	clang $(CFLAGS) probe/probe.c src/PrivateSensors.c \
	    -framework CoreFoundation -o build/probe

build:
	mkdir -p build

test:
	@true

clean:
	rm -rf build

.PHONY: all clean test probe

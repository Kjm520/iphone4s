# Builds GPSBag.app for armv7 / iOS 8.0. Runs on the build Mac
# (Apple clang 14 + ld64 820 + theos iPhoneOS9.3.sdk with the liblaunch stub;
# see tools/ in the repo for how that SDK is set up).
SDK        := $(HOME)/ios/sdks/iPhoneOS9.3.sdk
TARGET     := -target armv7-apple-ios8.0
WARN       := -Wall -Wextra
CFLAGS     := $(TARGET) -isysroot $(SDK) -O2 $(WARN) -I../shared
OBJCFLAGS  := $(CFLAGS) -fobjc-arc
FRAMEWORKS := -framework UIKit -framework CoreLocation -framework Foundation \
              -framework CoreGraphics -framework QuartzCore

APP   := build/TrackBag.app
SRC_M := $(wildcard src/*.m)
SRC_C := $(wildcard src/*.c) $(wildcard ../shared/*.c)
OBJ   := $(SRC_M:src/%.m=build/obj/%.o) \
         $(patsubst %.c,build/obj/%.o,$(notdir $(SRC_C)))

all: $(APP)/TrackBag $(APP)/Info.plist $(APP)/Icon-60@2x.png

$(APP)/Icon-60@2x.png: Resources/Icon-60@2x.png | $(APP)
	cp $< $@

build/obj/%.o: src/%.m src/*.h | build/obj
	clang $(OBJCFLAGS) -c $< -o $@

build/obj/%.o: src/%.c src/*.h | build/obj
	clang $(CFLAGS) -c $< -o $@

build/obj/%.o: ../shared/%.c ../shared/%.h | build/obj
	clang $(CFLAGS) -c $< -o $@

$(APP)/TrackBag: $(OBJ) | $(APP)
	clang $(TARGET) -isysroot $(SDK) $(OBJ) $(FRAMEWORKS) -o $@

$(APP)/Info.plist: Resources/Info.plist | $(APP)
	cp $< $@

build/obj $(APP):
	mkdir -p $@

# Geodesy unit tests, compiled natively for this Mac and executed here.
test: | build
	clang -O1 $(WARN) -I../shared test/geo_test.c ../shared/Geo.c \
	    -o build/geo_test -lm
	./build/geo_test

build:
	mkdir -p build

clean:
	rm -rf build

.PHONY: all clean test

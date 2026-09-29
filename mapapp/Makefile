# Builds MapBag.app for armv7 / iOS 8.0 on the build Mac. Same toolchain
# story as ../app/Makefile.
SDK        := $(HOME)/ios/sdks/iPhoneOS9.3.sdk
TARGET     := -target armv7-apple-ios8.0
WARN       := -Wall -Wextra
CFLAGS     := $(TARGET) -isysroot $(SDK) -O2 $(WARN) -I../shared
OBJCFLAGS  := $(CFLAGS) -fobjc-arc
FRAMEWORKS := -framework UIKit -framework MapKit -framework CoreLocation \
              -framework Foundation -framework CoreGraphics -framework QuartzCore
LIBS       := -lsqlite3

APP   := build/MapBag.app
SRC_M := $(wildcard src/*.m)
SRC_C := $(wildcard ../shared/*.c)
OBJ   := $(SRC_M:src/%.m=build/obj/%.o) \
         $(patsubst %.c,build/obj/%.o,$(notdir $(SRC_C)))

all: $(APP)/MapBag $(APP)/Info.plist $(APP)/Icon-60@2x.png

$(APP)/Icon-60@2x.png: Resources/Icon-60@2x.png | $(APP)
	cp $< $@

build/obj/%.o: src/%.m src/*.h | build/obj
	clang $(OBJCFLAGS) -c $< -o $@

build/obj/%.o: ../shared/%.c ../shared/%.h | build/obj
	clang $(CFLAGS) -c $< -o $@

$(APP)/MapBag: $(OBJ) | $(APP)
	clang $(TARGET) -isysroot $(SDK) $(OBJ) $(FRAMEWORKS) $(LIBS) -o $@

$(APP)/Info.plist: Resources/Info.plist | $(APP)
	cp $< $@

build/obj $(APP):
	mkdir -p $@

# No host-testable logic yet; the target exists so deploy.py can stay uniform.
test:
	@true

clean:
	rm -rf build

.PHONY: all clean test

PREFIX ?= /usr/local
BINDIR := $(PREFIX)/bin
MANDIR := $(PREFIX)/share/man/man1

# Swift Testing ships inside Xcode; with only the Command Line Tools installed the
# frameworks live under CommandLineTools and need explicit search paths.
CLT := /Library/Developer/CommandLineTools
ifeq ($(wildcard $(CLT)/Library/Developer/Frameworks/Testing.framework),)
  TEST_FLAGS :=
else ifeq ($(shell xcode-select -p 2>/dev/null),$(CLT))
  TEST_FLAGS := --disable-xctest --enable-swift-testing \
    -Xswiftc -F$(CLT)/Library/Developer/Frameworks \
    -Xlinker -F$(CLT)/Library/Developer/Frameworks \
    -Xlinker -rpath -Xlinker $(CLT)/Library/Developer/Frameworks \
    -Xlinker -rpath -Xlinker $(CLT)/Library/Developer/usr/lib
else
  TEST_FLAGS :=
endif

all: build

build:
	swift build -c release --disable-sandbox $(FLAGS)

debug:
	swift build --disable-sandbox $(FLAGS)

universal:
	swift build -c release --disable-sandbox --arch arm64 --arch x86_64 $(FLAGS)

install: build
	install -d "$(DESTDIR)$(BINDIR)"
	install -m 755 ".build/release/share" "$(DESTDIR)$(BINDIR)/share"
	@if [ -f docs/man/share.1 ]; then \
		install -d "$(DESTDIR)$(MANDIR)"; \
		install -m 644 docs/man/share.1 "$(DESTDIR)$(MANDIR)/share.1"; \
	fi
	@echo "Installed $(DESTDIR)$(BINDIR)/share. Run 'share completions --install' for tab completion."

uninstall:
	rm -f "$(DESTDIR)$(BINDIR)/share" "$(DESTDIR)$(MANDIR)/share.1"

test:
	swift test --disable-sandbox $(TEST_FLAGS) $(FLAGS)

man:
	swift package --allow-writing-to-package-directory generate-manual --output-directory docs/man

smoke: debug
	./scripts/smoke.sh .build/debug/share

clean:
	rm -rf .build

.PHONY: all build debug universal install uninstall test man smoke clean

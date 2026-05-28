PREFIX ?= /usr/local
BINDIR := $(PREFIX)/bin

all: build

build:
	swift build -c release --disable-sandbox $(FLAGS)

install: build
	install -d $(DESTDIR)$(BINDIR)
	install -m 755 ".build/release/share" "$(DESTDIR)$(BINDIR)"

uninstall:
	rm -rf $(DESTDIR)$(BINDIR)/share

test:
	swift test --disable-sandbox

clean:
	rm -rf .build

.PHONY: all build install uninstall test clean

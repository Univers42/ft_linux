# watchdog — built statically so the one binary runs in any container/host.
# Built inside the builder image (see top-level `make watchdog`); output goes to
# the gitignored build/ tree, never the host.
CC      ?= cc
CFLAGS  ?= -O2 -Wall -Wextra -Werror -std=c11 -static
BIN     ?= watchdog
SRC     := watchdog.c

$(BIN): $(SRC)
	$(CC) $(CFLAGS) -o $(BIN) $(SRC)

clean:
	rm -f $(BIN)

.PHONY: clean

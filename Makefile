# Makefile for sqlite3d project
# Handles SQLite3 library compilation as preBuildCommands

# Variables
CC = cc
AR = ar
SQLITE_DIR = libs/sqlite
SQLITE_SRC = $(SQLITE_DIR)/sqlite3.c
SQLITE_OBJ = $(SQLITE_DIR)/sqlite3.o
SQLITE_LIB = $(SQLITE_DIR)/sqlite3.a
SQLITE_WRAPPER = $(SQLITE_DIR)/lited.c
SQLITE_CLI_SRC = $(SQLITE_DIR)/shell.c
SQLITE_CLI=$(SQLITE_DIR)/sqlite3
LITED = ./lited

# Default target
all: prebuild

# PreBuild commands equivalent
prebuild: $(SQLITE_LIB) $(SQLITE_WRAPPER) $(SQLITE_CLI)
	@echo "PreBuild commands completed successfully"

# Compile SQLite3 object file
$(SQLITE_OBJ): $(SQLITE_SRC)
	@echo "Compiling SQLite3 object file..."
	@mkdir -p $(SQLITE_DIR)
	$(CC) -c $(SQLITE_SRC) -DSQLITE_DQS=0 -fPIC -o $(SQLITE_OBJ)

# Create SQLite3 static library
$(SQLITE_LIB): $(SQLITE_OBJ)
	@echo "Creating SQLite3 static library..."
	$(AR) rcs $(SQLITE_LIB) $(SQLITE_OBJ)

# Generate SQLite wrapper
$(SQLITE_WRAPPER):
	@echo "Generating SQLite wrapper..."
	@mkdir -p $(SQLITE_DIR)
	@echo '#include "sqlite3.h"' > $(SQLITE_WRAPPER)

$(SQLITE_CLI): $(SQLITE_SRC) $(SQLITE_CLI_SRC)
	@echo "Generating SQLite cli"
	@mkdir -p $(SQLITE_DIR)
	$(CC) -DSQLITE_THREADSAFE=0 $(SQLITE_CLI_SRC) $(SQLITE_SRC) -DSQLITE_DQS=0 -ldl -lm -o $(SQLITE_CLI)

# Clean targets
clean:
	@echo "Cleaning build artifacts..."
	@dub clean
	@rm -f $(SQLITE_OBJ) $(SQLITE_LIB) $(SQLITE_WRAPPER) $(LITED) $(SQLITE_CLI)
	@rm -rf $(SQLITE_DIR) *.sqlite

clean-all: clean
	@echo "Cleaning all generated files..."

# Force rebuild
rebuild: clean all

# Check if required source files exist
check:
	@echo "Checking prerequisites..."
	@if [ ! -f $(SQLITE_SRC) ]; then \
		echo "Error: $(SQLITE_SRC) not found!"; \
		exit 1; \
	fi
	@echo "All prerequisites satisfied"

# Help target
help:
	@echo "Available targets:"
	@echo "  all	   - Run prebuild commands (default)"
	@echo "  prebuild  - Execute preBuildCommands equivalent"
	@echo "  clean	 - Remove build artifacts"
	@echo "  clean-all - Remove all generated files"
	@echo "  rebuild   - Clean and rebuild"
	@echo "  check	 - Verify prerequisites"
	@echo "  help	  - Show this help"

# Phony targets
.PHONY: all prebuild clean clean-all rebuild check help

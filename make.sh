#!/usr/bin/env bash

# --- Initialization ---
set -eu  # Enchanced debugging and error handling

# Save original environment variables
ORIGINAL_GOOS="$(go env GOOS)"
ORIGINAL_GOARCH="$(go env GOARCH)"
ORIGINAL_CGO_ENABLED="${CGO_ENABLED:-1}"  # Default to 1 if not set

# Default values
DEFAULT_OS="$ORIGINAL_GOOS"
DEFAULT_ARCH="$ORIGINAL_GOARCH"
DEFAULT_SRC="main.go"
DEFAULT_EXEC="main"

# Variables to store values
TARGET_OS="$DEFAULT_OS"
TARGET_ARCH="$DEFAULT_ARCH"
SRC_PATH="$DEFAULT_SRC"
EXEC_PATH="$DEFAULT_EXEC"
CUSTOM_CONFIG=""  # Variable to store the custom config file path

# Acceptable values for OS and Architecture
VALID_OS="linux freebsd windows darwin"  # Add more as needed
VALID_ARCH="amd64 arm arm64"          # Add more as needed

# Define color codes
GREEN='\e[32m'
RED='\e[31m'
BLUE='\e[34m'
PURPLE='\e[35m'
RESET='\e[0m'

# Function to print usage help
print_usage() {
  colored_echo "Usage: $0 [-o os] [-a arch] [-s source] [-t target] [-c config_file]"
  colored_echo "  -o os          : Target operating system. Default: current OS ($(go env GOOS))."
  colored_echo "                   Acceptable values: $VALID_OS"
  colored_echo "  -a arch        : Target architecture. Default: current architecture ($(go env GOARCH))."
  colored_echo "                   Acceptable values: $VALID_ARCH"
  colored_echo "  -s source      : Source file or path. Default: ./main.go"
  colored_echo "  -t target      : Executable binary file or path. Default: ./main"
  colored_echo "  -c config_file : Specify a custom configuration file."
  colored_echo "Options can appear in any order."
  colored_echo "A 'conf.make' file in the current directory is loaded by default if it exists."
  colored_echo "'conf.make' or custom make files can contain any of the functions that overrides default config."
  colored_echo "A line in .make file should contain a single option flag and its value, example: '-t ./bin/main'."
  colored_echo "Command-line arguments override 'conf.make' and any custom config file."
}

# Function to print colored colored_echo messages
colored_echo() {
  local message="$1"
  local msg_length="${#message}"
  local prefix
  local suffix
  local middle_message

  if [[ "$msg_length" -lt 4 ]]; then
    echo "$message" # Message too short for prefix/suffix coloring, print as is
    return
  fi

  prefix="${message:0:2}" # Extract first two characters (now safe as length is >= 4)

  case "$prefix" in
    "++"|"--"|"//"|"==") # Only process if prefix is one of the defined ones
      suffix="${message:$((${msg_length}-2)):2}" # Extract last two characters
      middle_message="${message:2:$((${msg_length}-4))}" # Extract middle part

      if [[ "$prefix" == "$suffix" ]]; then
        case "$prefix" in
          "++") echo -e "${GREEN}${prefix}${RESET}${middle_message}${GREEN}${suffix}${RESET}";;
          "--") echo -e "${RED}${prefix}${RESET}${middle_message}${RED}${suffix}${RESET}";;
          "//") echo -e "${BLUE}${prefix}${RESET}${middle_message}${BLUE}${suffix}${RESET}";;
          "==") echo -e "${PURPLE}${prefix}${RESET}${middle_message}${PURPLE}${suffix}${RESET}";;
        esac
      else
        case "$prefix" in
          "++") echo -e "${GREEN}${prefix}${RESET}${message:2}";; # Color only prefix
          "--") echo -e "${RED}${prefix}${RESET}${message:2}";;  # Color only prefix
          "//") echo -e "${BLUE}${prefix}${RESET}${message:2}";; # Color only prefix
          "==") echo -e "${PURPLE}${prefix}${RESET}${message:2}";; # Color only prefix
        esac
      fi
      ;;
    *)
      echo "$message" # No color for other messages without defined prefix
      ;;
  esac
}

# --- Local Configuration File Parsing (conf.make) ---

if [ -f "conf.make" ]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      -o*) TARGET_OS="${line#*-o }" ;;
      -a*) TARGET_ARCH="${line#*-a }" ;;
      -s*) SRC_PATH="${line#*-s }" ;;
      -t*) EXEC_PATH="${line#*-t }" ;;
      *) ;;  # Ignore lines that don't match the pattern
    esac
  done < "conf.make"
fi

# --- Argument Parsing ---

while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -o)
      TARGET_OS="$2"
      shift # past argument
      shift # past value
      ;;
    -a)
      TARGET_ARCH="$2"
      shift # past argument
      shift # past value
      ;;
    -s)
      SRC_PATH="$2"
      shift # past argument
      shift # past value
      ;;
    -t)
      EXEC_PATH="$2"
      shift # past argument
      shift # past value
      ;;
    -c)
      CUSTOM_CONFIG="$2"  # Store the custom config file path
      shift # past argument
      shift # past value
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      colored_echo "-- Error: Unknown option: $key --"
      print_usage
      exit 1
      ;;
  esac
done

# --- Custom Configuration File Parsing (if specified) ---

if [ -n "$CUSTOM_CONFIG" ]; then
  if [ ! -f "$CUSTOM_CONFIG" ]; then
    colored_echo "-- Error: Custom config file not found: $CUSTOM_CONFIG --"
    exit 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      -o*) TARGET_OS="${line#*-o }" ;;
      -a*) TARGET_ARCH="${line#*-a }" ;;
      -s*) SRC_PATH="${line#*-s }" ;;
      -t*) EXEC_PATH="${line#*-t }" ;;
      *) ;;  # Ignore lines that don't match the pattern
    esac
  done < "$CUSTOM_CONFIG"
fi

# --- Validation ---

# Validate OS
if [[ ! " $VALID_OS " =~ " $TARGET_OS " ]]; then
  colored_echo "-- Error: Invalid OS specified: $TARGET_OS --"
  colored_echo "   Acceptable values: $VALID_OS"
  exit 1
fi

# Validate Architecture
if [[ ! " $VALID_ARCH " =~ " $TARGET_ARCH " ]]; then
  colored_echo "-- Error: Invalid architecture specified: $TARGET_ARCH --"
  colored_echo "   Acceptable values: $VALID_ARCH"
  exit 1
fi

# --- Compilation ---

colored_echo "== Updating dependencies =="
go get -u ./...
go mod tidy

# Disable CGO if enabled
if [ "${CGO_ENABLED:-1}" != "0" ]; then
  colored_echo "// Warning: CGO_ENABLED is being set to 0 for cross-compilation."
  colored_echo "// If your program requires CGO, please modify this script."
  export CGO_ENABLED=0
fi

colored_echo "== Compiling for ${TARGET_OS} ${TARGET_ARCH} =="
export GOOS="$TARGET_OS"
export GOARCH="$TARGET_ARCH"
go build -o "$EXEC_PATH" "$SRC_PATH"

if [ $? -eq 0 ]; then
  colored_echo "++ Compilation successful. ${TARGET_OS} ${TARGET_ARCH} executable created at ${EXEC_PATH} ++"
else
  colored_echo "-- Compilation failed for ${TARGET_OS} ${TARGET_ARCH}. --"
fi

# --- Cleanup ---

# Restore original environment variables
export GOOS="$ORIGINAL_GOOS"
export GOARCH="$ORIGINAL_GOARCH"
export CGO_ENABLED="$ORIGINAL_CGO_ENABLED"

colored_echo "// Environment restored to original settings (if applicable)."
colored_echo "== Done! =="

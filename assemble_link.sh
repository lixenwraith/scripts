#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
# Treat unset variables as an error when substituting.
# set -e # Optional: uncomment if you want script to exit on first error instead of checking $?
set -u

# --- Configuration ---
ASSEMBLER="as"
LINKER="gcc"
LINKER_FLAGS="-nostdlib -static"
DEFAULT_OUTPUT_NAME="main"
ALLOWED_EXTENSIONS=("s" "as" "asm")

# --- Helper Functions ---
usage() {
  echo "Usage: $0 <folder_path>"
  echo "  Assembles *.s, *.as, *.asm files in <folder_path> using '$ASSEMBLER'"
  echo "  Links the resulting .o files using '$LINKER $LINKER_FLAGS'"
  echo "  Output name is the base filename if only one assembly file exists,"
  echo "  otherwise it defaults to '$DEFAULT_OUTPUT_NAME'."
  exit 1
}

echowarn() {
  echo "[WARNING] $1"
}

echoerr() {
  echo "[ERROR] $1" >&2
}

echoinfo() {
  echo "[INFO] $1"
}

# --- Argument Parsing ---
if [[ "$#" -ne 1 ]]; then
  echoerr "Exactly one argument (the folder path) is required."
  usage
fi

TARGET_DIR="$1"

if [[ ! -d "$TARGET_DIR" ]]; then
  echoerr "Folder not found: '$TARGET_DIR'"
  exit 1
fi

# --- Find Assembly Files ---
echoinfo "Searching for assembly files (.s, .as, .asm) in '$TARGET_DIR'..."
# Use find and process substitution to handle filenames with spaces correctly
ASSEMBLY_FILES=()
while IFS= read -r -d $'\0' file; do
  ASSEMBLY_FILES+=("$file")
done < <(find "$TARGET_DIR" -maxdepth 1 \( -name "*.s" -o -name "*.as" -o -name "*.asm" \) -print0)

if [[ ${#ASSEMBLY_FILES[@]} -eq 0 ]]; then
  echoinfo "No assembly files found in '$TARGET_DIR'. Exiting."
  exit 0
fi

echoinfo "Found ${#ASSEMBLY_FILES[@]} assembly file(s):"
printf "  %s\n" "${ASSEMBLY_FILES[@]}"

# --- Check for Base Name Conflicts ---
declare -A BASE_NAMES
HAS_CONFLICT=0
for file in "${ASSEMBLY_FILES[@]}"; do
    BASENAME=$(basename "$file")
    NAME_NO_EXT="${BASENAME%.*}"
    if [[ -v BASE_NAMES["$NAME_NO_EXT"] ]]; then
        # Conflict detected
        CONFLICTING_FILE="${BASE_NAMES["$NAME_NO_EXT"]}"
        echoerr "Multiple assembly files found for base name '$NAME_NO_EXT':"
        echoerr "  - $CONFLICTING_FILE"
        echoerr "  - $file"
        HAS_CONFLICT=1
    else
        BASE_NAMES["$NAME_NO_EXT"]="$file"
    fi
done

if [[ "$HAS_CONFLICT" -ne 0 ]]; then
    echoerr "Please resolve the conflicts by removing or renaming duplicate files."
    exit 1
fi
echoinfo "No base name conflicts found."

# --- Prepare for Assembly ---
OBJECT_FILES=()
POTENTIAL_OBJ_FILES_EXIST=()
for asm_file in "${ASSEMBLY_FILES[@]}"; do
  base_name=$(basename "$asm_file")
  obj_file="$TARGET_DIR/${base_name%.*}.o"
  OBJECT_FILES+=("$obj_file")
  if [[ -e "$obj_file" ]]; then
      POTENTIAL_OBJ_FILES_EXIST+=("$obj_file")
  fi
done

# --- Check for Existing Object Files ---
if [[ ${#POTENTIAL_OBJ_FILES_EXIST[@]} -gt 0 ]]; then
    echowarn "The following object files already exist and will be overwritten:"
    printf "  %s\n" "${POTENTIAL_OBJ_FILES_EXIST[@]}"
    read -p "Press Enter to continue or Ctrl+C to abort..."
fi

# --- Assemble Files ---
echoinfo "Assembling files..."
i=0
for asm_file in "${ASSEMBLY_FILES[@]}"; do
  obj_file="${OBJECT_FILES[$i]}"
  echoinfo "  Assembling '$asm_file' -> '$obj_file'"
  "$ASSEMBLER" "$asm_file" -o "$obj_file"
  if [[ $? -ne 0 ]]; then
    echoerr "Assembly failed for '$asm_file'."
    # Optional: Clean up already created .o files? For simplicity, we don't here.
    exit 1
  fi
  ((i++))
done
echoinfo "Assembly successful."

# --- Determine Output Executable Name ---
OUTPUT_EXE_NAME=""
if [[ ${#ASSEMBLY_FILES[@]} -eq 1 ]]; then
  # Use the base name of the single assembly file
  base_name=$(basename "${ASSEMBLY_FILES[0]}")
  OUTPUT_EXE_NAME="${base_name%.*}"
else
  # Default name for multiple files
  OUTPUT_EXE_NAME="$DEFAULT_OUTPUT_NAME"
fi
OUTPUT_EXE_PATH="$TARGET_DIR/$OUTPUT_EXE_NAME"

# --- Check for Existing Executable ---
if [[ -e "$OUTPUT_EXE_PATH" ]]; then
    echowarn "Executable '$OUTPUT_EXE_PATH' already exists and will be overwritten."
    read -p "Press Enter to continue or Ctrl+C to abort..."
fi

# --- Link Object Files ---
echoinfo "Linking ${#OBJECT_FILES[@]} object file(s) into '$OUTPUT_EXE_PATH'..."
echoinfo "  Command: $LINKER $LINKER_FLAGS ${OBJECT_FILES[*]} -o $OUTPUT_EXE_PATH" # Use [*] for display
"$LINKER" $LINKER_FLAGS "${OBJECT_FILES[@]}" -o "$OUTPUT_EXE_PATH" # Use [@] for execution

if [[ $? -ne 0 ]]; then
  echoerr "Linking failed."
  # Optional: Clean up .o files?
  exit 1
fi

echoinfo "Linking successful. Executable created at '$OUTPUT_EXE_PATH'."

# Optional: Clean up intermediate object files
# read -p "Linking successful. Remove intermediate object files (.o)? [y/N] " -n 1 -r
# echo # Move to a new line
# if [[ $REPLY =~ ^[Yy]$ ]]; then
#     echoinfo "Removing object files..."
#     rm -f "${OBJECT_FILES[@]}"
#     echoinfo "Object files removed."
# fi

exit 0

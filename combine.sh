#!/bin/bash

echo "--- Script Start ---" >&2

# --- Strict Mode ---
# set -e # Keep commented, or fails due to piping std out to file
set -u
set -o pipefail
echo "--- Strict Mode Set (set -e temporarily disabled globally) ---" >&2

# --- Configuration ---
OUTPUT_FILE=""
DEFAULT_OUTPUT_FILE="./combined.txt"
FILE_EXTENSION=""
RECURSIVE=false
declare -a DIRS_TO_SCAN=()
echo "--- Configuration Initialized ---" >&2

# --- Colors ---
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  YELLOW='\033[0;33m'
  CYAN='\033[0;36m'
  NC='\033[0m' # No Color
else
  RED=''
  YELLOW=''
  CYAN=''
  NC=''
fi
echo "--- Colors Set ---" >&2

# --- Global Counters ---
file_count=0
total_lines=0
skipped_count=0
loop_errors=0 # Counter for errors inside the loop
echo "--- Counters Initialized (files=$file_count, lines=$total_lines, skipped=$skipped_count, loop_errors=$loop_errors) ---" >&2

# --- Functions ---
# UPDATED usage function with detailed descriptions
usage() {
  cat << EOF >&2
Usage: $0 [options] <dir1> [dir2] ...

A utility to combine multiple text files from specified directories into a single file.
Each included file's content is preceded by a header comment indicating its original path.

Options:
  -o <file>     Specify the path for the output file.
                If not provided, defaults to '${DEFAULT_OUTPUT_FILE}'.

  -e <ext>      Filter files by a specific extension (e.g., 'py', 'txt', 'md').
                The leading dot is optional and will be added if missing.
                If omitted, all files are included.

  -r            Enable recursive search. The script will look for files in the
                specified directories and all of their subdirectories.

  -h, --help    Display this help message and exit.

Arguments:
  <dir>         One or more directories to scan for files. This is a required
                argument.

Example:
  # Recursively find all '.js' and '.css' files in the 'src' directory
  # and combine them into a single file named 'project-bundle.txt'.
  $0 -r -e js -o project-bundle.txt ./src/
EOF
  exit 1
}
echo "--- Usage Function Defined ---" >&2

# --- Argument Parsing ---
echo "--- Starting Argument Parsing ---" >&2
while [[ $# -gt 0 ]]; do
  key="$1"
  echo "DEBUG: Parsing argument: '$key'" >&2
  case $key in
    -o)
      if [[ -z "${2:-}" ]]; then echo -e "${RED}Error:${NC} -o requires argument." >&2; usage; fi
      OUTPUT_FILE="$2"; echo "DEBUG: Set OUTPUT_FILE='$OUTPUT_FILE'" >&2; shift 2 ;;
    -e)
      if [[ -z "${2:-}" ]]; then echo -e "${RED}Error:${NC} -e requires argument." >&2; usage; fi
      if [[ "$2" != .* ]]; then FILE_EXTENSION=".$2"; echo -e "${YELLOW}Info:${NC} Added leading dot: using '${FILE_EXTENSION}'" >&2; else FILE_EXTENSION="$2"; fi
      echo "DEBUG: Set FILE_EXTENSION='$FILE_EXTENSION'" >&2; shift 2 ;;
    -r)
      RECURSIVE=true; echo "DEBUG: Set RECURSIVE=true" >&2; shift ;;
    -h|--help)
      usage ;;
    *)
      if [[ "$1" == -* ]]; then echo -e "${RED}Error:${NC} Unknown option '$1'." >&2; usage; fi
      DIRS_TO_SCAN+=("$1"); echo "DEBUG: Added directory to scan: '$1'" >&2; shift ;;
  esac
done
echo "--- Finished Argument Parsing ---" >&2
echo "DEBUG: Final DIRS_TO_SCAN: ${DIRS_TO_SCAN[*]}" >&2
echo "DEBUG: Final OUTPUT_FILE: '$OUTPUT_FILE'" >&2
echo "DEBUG: Final FILE_EXTENSION: '$FILE_EXTENSION'" >&2
echo "DEBUG: Final RECURSIVE: $RECURSIVE" >&2

# --- Validation ---
echo "--- Starting Validation ---" >&2
if [[ ${#DIRS_TO_SCAN[@]} -eq 0 ]]; then echo -e "${RED}Error:${NC} No directories specified." >&2; usage; fi
echo "--- Validation Passed ---" >&2

# --- Core Logic ---
combine_files() {
  echo "--- Entering combine_files function ---" >&2
  local first_file_processed=true
  local find_cmd_base="find"
  local find_args=()
  local name_filter='*'
  local header_echo_status=0
  local cat_status=0
  local wc_status=0

  if [[ -n "$FILE_EXTENSION" ]]; then
      name_filter="*${FILE_EXTENSION}"
       echo "DEBUG (combine_files): Set name_filter='$name_filter'" >&2
  fi

  for dir in "${DIRS_TO_SCAN[@]}"; do
    echo "--- Processing directory: '$dir' ---" >&2
    if [[ ! -d "$dir" ]]; then
      echo -e "${YELLOW}Warning:${NC} '$dir' is not a valid directory. Skipping." >&2
      continue
    fi

    find_args=("$dir")
    if [[ "$RECURSIVE" = false ]]; then find_args+=("-maxdepth" "1"); fi
    find_args+=("-type" "f" "-name" "$name_filter" "-print0")
    echo "DEBUG (combine_files): Constructed find command args for '$dir': ${find_args[*]}" >&2

    echo "DEBUG (combine_files): Preparing to execute find and read results for '$dir'..." >&2
    local find_cmd_str="$find_cmd_base ${find_args[*]} 2>/dev/null | sort -z"
    echo "DEBUG (combine_files): Effective command in process substitution: $find_cmd_str" >&2

    # --- Temporarily disable set -e INSIDE the loop ---
    # Use 'while command || true' to prevent loop exit on read error if pipe breaks early
    while IFS= read -r -d $'\0' file_path || [[ -n "$file_path" ]]; do # Process even incomplete last line
      echo "--- Found potential file: '$file_path' ---" >&2

      # Check readability
      echo "DEBUG (combine_files): Checking readability for '$file_path'..." >&2
      if [[ ! -r "$file_path" ]]; then
          echo -e "${YELLOW}Warning:${NC} Cannot read '$file_path'. Skipping." >&2
          ((skipped_count++)); echo "DEBUG (combine_files): Incremented skipped_count=$skipped_count" >&2
          continue
      fi
      echo "DEBUG (combine_files): File '$file_path' is readable." >&2

      # Add separator newline
      if [[ "$first_file_processed" = false ]]; then
        echo "DEBUG (combine_files): Adding separator newline." >&2
        echo "" # Add blank line separator TO STDOUT
        local separator_echo_status=$?
        echo "DEBUG (combine_files): Separator echo status: $separator_echo_status" >&2
        if [[ $separator_echo_status -ne 0 ]]; then
            echo -e "${RED}Error:${NC} Failed to echo separator for '$file_path'. Status: $separator_echo_status" >&2
            ((loop_errors++)); continue
        fi
        ((total_lines++)); echo "DEBUG (combine_files): Incremented total_lines for separator: $total_lines" >&2
      else
        echo "DEBUG (combine_files): This is the first file processed, no separator needed yet." >&2
      fi
      # Mark that we intend to process this file fully
      first_file_processed=false

      # Increment processed file counter *tentatively*
      ((file_count++)); echo "DEBUG (combine_files): Incremented file_count=$file_count" >&2

      # Prepare header
      filename=$(basename "$file_path")
      relative_path="${file_path#"$dir"/}"; if [[ "$relative_path" == "$file_path" ]]; then relative_path="${file_path#./}"; fi
      header="// --- File: $relative_path ---"
      echo "DEBUG (combine_files): Prepared header: '$header'" >&2

      # Print header TO STDOUT and CHECK STATUS
      echo "$header"
      header_echo_status=$?
      echo "DEBUG (combine_files): Header echo status: $header_echo_status" >&2
      if [[ $header_echo_status -ne 0 ]]; then
          echo -e "${RED}Error:${NC} Failed to echo header for '$file_path'. Status: $header_echo_status" >&2
          ((loop_errors++)); ((file_count--)); first_file_processed=true; # Decrement count, reset first flag if header fails
          echo "DEBUG (combine_files): Adjusted counters: errors=$loop_errors, files=$file_count" >&2
          continue # Skip rest of processing for this file
      fi
      ((total_lines++)); echo "DEBUG (combine_files): Incremented total_lines for header: $total_lines" >&2

      # Get line count and CHECK STATUS
      echo "DEBUG (combine_files): Getting line count for '$file_path'..." >&2
      # Ensure wc doesn't cause exit
      lines_in_file=$(wc -l < "$file_path")
      wc_status=$?
      echo "DEBUG (combine_files): wc -l status: $wc_status, lines found: $lines_in_file" >&2
      if [[ $wc_status -ne 0 ]]; then
          echo -e "${RED}Error:${NC} wc -l failed for '$file_path'. Status: $wc_status. Skipping file content." >&2
          ((loop_errors++)); ((skipped_count++)); ((file_count--)); # Count as skipped and error, revert file_count
          echo "DEBUG (combine_files): Adjusted counters: errors=$loop_errors, skipped=$skipped_count, files=$file_count" >&2
          continue
      fi
      total_lines=$((total_lines + lines_in_file))
      echo "DEBUG (combine_files): Incremented total_lines for file content: $total_lines (added $lines_in_file)" >&2

      # Output file content TO STDOUT and CHECK STATUS
      echo "DEBUG (combine_files): Executing 'cat \"$file_path\"' to output content..." >&2
      cat "$file_path"
      cat_status=$?
      echo "DEBUG (combine_files): 'cat \"$file_path\"' finished with status $cat_status." >&2
      if [[ $cat_status -ne 0 ]]; then
           echo -e "${RED}Error:${NC} cat failed for '$file_path'. Status: $cat_status. Output might be incomplete." >&2
           ((loop_errors++))
           # Don't decrement file_count here, as partial content might exist
      fi
       echo "--- Finished processing file: '$file_path' ---" >&2

    done < <( "$find_cmd_base" "${find_args[@]}" 2>/dev/null | sort -z )
    echo "--- Finished reading files found in '$dir' ---" >&2

  done # End of for loop iterating through directories
  echo "--- Exiting combine_files function ---" >&2
}

# --- Output Handling ---
echo "--- Determining Output File ---" >&2
FINAL_OUTPUT_FILE="${OUTPUT_FILE:-$DEFAULT_OUTPUT_FILE}"
echo "DEBUG: Raw FINAL_OUTPUT_FILE='$FINAL_OUTPUT_FILE'" >&2
output_dir=$(dirname "$FINAL_OUTPUT_FILE")
echo "DEBUG: Output directory determined as '$output_dir'" >&2
if [[ ! -d "$output_dir" ]]; then echo "DEBUG: Creating output directory '$output_dir'..."; mkdir -p "$output_dir"; echo "DEBUG: mkdir status: $?" >&2; fi
ABS_OUTPUT_PATH=""
if command -v realpath &> /dev/null; then ABS_OUTPUT_PATH=$(realpath "$FINAL_OUTPUT_FILE"); echo "DEBUG: Absolute path using realpath: '$ABS_OUTPUT_PATH'" >&2;
elif [[ "$FINAL_OUTPUT_FILE" == /* ]]; then ABS_OUTPUT_PATH="$FINAL_OUTPUT_FILE"; echo "DEBUG: Absolute path (already absolute): '$ABS_OUTPUT_PATH'" >&2;
else ABS_OUTPUT_PATH="$(pwd)/$FINAL_OUTPUT_FILE"; ABS_OUTPUT_PATH=$(echo "$ABS_OUTPUT_PATH" | sed -e 's#/\./#/#g' -e 's#/[^/]*/\.\./#/#g'); echo "DEBUG: Absolute path using pwd fallback: '$ABS_OUTPUT_PATH'" >&2; fi

echo -e "Combining files into: ${YELLOW}${ABS_OUTPUT_PATH}${NC}" >&2

# --- Execute Combination and Redirect ---
echo "--- Preparing to call combine_files and redirect output to '$FINAL_OUTPUT_FILE' ---" >&2
# Execute and capture the exit status of combine_files itself
combine_files > "$FINAL_OUTPUT_FILE"
combine_status=$?
echo "--- combine_files function call finished. Exit status: $combine_status ---" >&2

# --- Final Summary ---
echo "--- Generating Final Summary ---" >&2
echo -e "----------------------------------------" >&2
echo -e "      ${CYAN}Combination Complete${NC}" >&2
echo -e "----------------------------------------" >&2
echo -e " Directories scanned: ${CYAN}${DIRS_TO_SCAN[*]}${NC}" >&2
echo -e " File extension filter: ${CYAN}${FILE_EXTENSION:-'(all files)'}${NC}" >&2
echo -e " Recursive search: ${CYAN}${RECURSIVE}${NC}" >&2
echo -e " Files processed successfully: ${CYAN}${file_count}${NC}" >&2
if [[ "$skipped_count" -gt 0 ]]; then echo -e " Files skipped (unreadable/wc error): ${RED}${skipped_count}${NC}" >&2; fi
if [[ "$loop_errors" -gt 0 ]]; then echo -e " Errors during file processing (echo/cat): ${RED}${loop_errors}${NC}" >&2; fi
echo -e " Total lines expected in output: ${CYAN}${total_lines}${NC}" >&2
echo -e " Output file: ${YELLOW}${ABS_OUTPUT_PATH}${NC}" >&2
echo -e "----------------------------------------" >&2

# Check final status and output file
echo "--- Performing final output file check ---" >&2
final_size=0
if [[ -f "$FINAL_OUTPUT_FILE" ]]; then # Check if file exists before wc
    final_size=$(wc -c < "$FINAL_OUTPUT_FILE")
fi
echo "DEBUG: Final output file size: $final_size bytes." >&2

final_exit_code=0
if [[ "$combine_status" -ne 0 ]]; then
    echo -e "${RED}Error:${NC} combine_files function exited with status ${combine_status}." >&2
    final_exit_code=1
fi
if [[ "$loop_errors" -gt 0 ]]; then
    echo -e "${RED}Error:${NC} ${loop_errors} errors occurred during file processing loop." >&2
     final_exit_code=1
fi

if [[ "$file_count" -gt 0 && ! -s "$FINAL_OUTPUT_FILE" ]]; then
    echo -e "${RED}Error:${NC} Output file '$FINAL_OUTPUT_FILE' is empty (0 bytes) despite reporting ${file_count} processed files. Check DEBUG messages for echo/cat failures." >&2
    final_exit_code=1
elif [[ "$file_count" -eq 0 && "$skipped_count" -eq 0 && "$loop_errors" -eq 0 ]]; then
     echo -e "${YELLOW}Warning:${NC} No matching files were found or processed." >&2
elif [[ "$file_count" -gt 0 && -s "$FINAL_OUTPUT_FILE" ]]; then
     echo -e "${CYAN}Success:${NC} Output file '$FINAL_OUTPUT_FILE' created with size $final_size bytes." >&2
fi

echo "--- Script End ---" >&2
exit $final_exit_code

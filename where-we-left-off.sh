#!/bin/bash
# where-we-left-off.sh: Continue a folder traversal operation from where we left off last time, which may have failed midway.
# source ~/.local/bin/error_handler.sh
shopt -s dotglob nullglob     # Include hidden files in operations
set -o pipefail

PERSISTENT_FILE="$HOME/.where-we-left-off"
REST_TIME=0.01
mode="size"  # Default mode

usage() {
    echo "Usage: $0 [options] <source_directory> [destination_directory]"
    echo "Options:"
    echo "  -s, --status                Report interrupted progress"
    echo "      --clear                 Clear interrupted progress"
    echo "  -p, --print                 Print each filename"
    echo "  -z, --size                  Report total folder size only (default)"
    echo "  -d, --diff                  Report all source_directory contents whose time/size differs from destination_directory"
    echo "  -c, --copy                  Copy all source_directory contents to destination_directory"
    echo "  -l, --leftoff <last_path>   Override the last recorded successful operation; start at the next path afterwards."
    echo "  -r, --rest <time>           Seconds to rest in between each item visited, decimals allowed."
    echo "  -h, --help                  Display this help message"
    exit 1
}

# Process each file/directory based on the mode. Rest in between to reduce risk of overheating / disconnects / interruptions.
process_item() {
    local item="$1"
    sleep "$REST_TIME"

    max_length=$(($(tput cols) - 60))
    truncated_item="${item:$(( ${#item} > max_length ? -max_length : 0 ))}"
    [ ${#item} -gt $max_length ] && truncated_item="...$truncated_item"

    printf "\r\033[K%d files and %d bytes so far. Current: %s" "$count" "$total_size" "$truncated_item"
    if [[ "$mode" == "print" ]]; then echo; fi

    if [[ "$mode" == "diff" ]]; then compare_item "$item"; fi

    if [[ "$mode" == "copy" && -n "$DEST_DIR" ]]; then
      mkdir -p "$(dirname "$DEST_DIR${item#$SOURCE_DIR}")"
      local result="$(rsync -aiAPU --modify-window=3 --no-r --out-format="[%i] %f" "$item" "$DEST_DIR${item#$SOURCE_DIR}" 2>/dev/null)";
      [[ -n "$result" && "$result" != *"skipping directory"* ]] && printf "\r\033[K%s\n" "$result";
    fi

    if [[ -d "$item" ]]; then return; fi    # Stop here if it was a directory.
    add_stats "$item"
}

add_stats() {
    local item="$1"
    # Get the apparent size of the current file
    file_size=$(stat -c %s "$item")      # $(du -b "$item" | cut -f1)

    if ! [[ $file_size =~ ^[0-9]+$ ]]; then
        printf "\nError: Filesize check failed. The drive may have been disconnected while processing '%s'. Exiting.\n" "$item"
        exit 3
    fi

    total_size=$((total_size + file_size))
    count=$((count + 1))
}

# Only print file/folder names that differ.
compare_item() {
    local item="$1"
    if [[ ! -e "$DEST_DIR${item#$SOURCE_DIR}" ]]; then
        printf "\r\033[K%s\n" "$item"  # Destination doesn't exist at all
    elif [[ -f "$item" ]]; then
        # Compare file size
        src_size=$(stat -c %s "$item")
        dest_size=$(stat -c %s "$DEST_DIR${item#$SOURCE_DIR}")

        # Compare modification time
        src_mtime=$(stat -c %Y "$item")
        dest_mtime=$(stat -c %Y "$DEST_DIR${item#$SOURCE_DIR}")

        # Output full path if size or timestamp differs
        if [[ "$src_size" != "$dest_size" ]] || [[ "$src_mtime" != "$dest_mtime" ]]; then
            printf "\r\033[K%s\n" "$item"
        fi
    fi
}

count=0
total_size=0

if [[ -f "$PERSISTENT_FILE" ]]; then
  IFS='|' read -r previous_item count total_size < "$PERSISTENT_FILE"
fi

TEMP=$(getopt -o spzdcl:r:h --long status,clear,print,size,diff,copy,leftoff:,rest:,help -n 'where-we-left-off.sh' -- "$@")
if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi
eval set -- "$TEMP"

# Set options:
while true ; do
    case "$1" in
        -s|--status) echo "Left off at: ${previous_item:-"No progress stored."} Items processed: $count Size so far: $total_size" ;
            exit 0 ; shift ;;
           --clear) rm $PERSISTENT_FILE ; exit 0 ; shift ;;
        -p|--print) mode="print" ; shift ;;
        -z|--size)  mode="size" ; shift ;;
        -d|--diff)  mode="diff" ; shift ;;
        -c|--copy)  mode="copy" ; shift ;;
        -l|--leftoff) previous_item=$2 shift 2 ;;
        -r|--rest)
            isnum() { awk -v a="$1" 'BEGIN {exit !(a == a + 0)}'; }
            isnum "$2" && REST_TIME="$2"
            shift 2 ;;
        -h|--help) usage ; exit 0 ;;
        --) shift ; break ;;
        *) echo "Invalid option $1" ; exit 1 ;;
    esac
done
[ -e "$previous_item" ] && previous_item=$(realpath "${previous_item%/}")   # No trailing slash

SOURCE_DIR=$(realpath "${1%/}")
if [[ -z "$1" || ! -d "$SOURCE_DIR" ]]; then
    echo "Error: Source directory not valid."
    usage
fi

# Optional destination directory input
if [[ $# -ge 2 ]]; then
    DEST_DIR=$(realpath "${2%/}")
    if [[ ! -d "$DEST_DIR" ]]; then
        echo "Error: Destination directory not valid."
        usage
    fi
fi

# If a starting directory is not provided by user or contained in persistent file, begin at the SOURCE_DIR root.
[ -e "$previous_item" ] && current_item="$(dirname "$previous_item")"
current_item="${current_item:-$SOURCE_DIR}"

if [[ "$current_item" != "$SOURCE_DIR"* ]]; then
    printf "Error: The last recorded path is outside the specified directory. Exiting...\n"
    exit 2
fi

# Main loop for directory traversal
while true; do
    entering_subfolder=false

    [ -f "$current_item" ] && folder="$(dirname "$current_item")" || folder="$current_item"

    # Try to list and process this directory's contents if connection to the drive hasn't failed yet
    if ! contents=$(find "$folder" -maxdepth 1 -mindepth 1 -exec realpath {} + | sort); then
        printf "\nFailed to access: %s\n" "$current_item"
        exit 4
    fi

    # Trim already-visited folder contents, through $previous_item if it's one of the lines.
    if trimmed=$(awk -v prev="$previous_item" '
        $0 == prev {found=1; next}
        found {print}
        END {if (!found) exit 1}
    ' <<< "$contents"); then
        contents="$trimmed"
    fi

    # Process directory contents
    while IFS= read -r item; do
        [ -z "$item" ] && continue  # Handle empty string from read -r due to empty $contents
        process_item "$item"

        if [ -d "$item" ]; then
            entering_subfolder=true
            current_item="$item"
            break  # Break out to process this new directory first.
        fi
        previous_item="$item"
        echo "$previous_item|$count|$total_size" > "$PERSISTENT_FILE"
    done <<< "$contents"

    # Check for final state: If we reached SOURCE_DIR and all items were processed.
    if [[ "$SOURCE_DIR" =~ ^"$current_item"/?$ ]] && ! $entering_subfolder; then
        if [[ -f "$PERSISTENT_FILE" ]]; then
          cat "$PERSISTENT_FILE" >> "${PERSISTENT_FILE}.archive"
          rm "$PERSISTENT_FILE"
        fi
        break  # Exit the loop after finishing.
    fi

    # Move up to parent directory if all items processed.
    if ! $entering_subfolder; then
        previous_item="$folder"
        echo "$previous_item|$count|$total_size" > "$PERSISTENT_FILE"
        current_item="$(dirname "$folder")"
    fi
done

printf "\r\033[KAll done. Processed %d files with a final size of %d bytes.\n" "$count" "$total_size"


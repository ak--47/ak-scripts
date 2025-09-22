#!/bin/bash

# list_bucket_folders: Human-readable tree of folders in a bucket/prefix (GCS)
# Usage:
#   list_bucket_folders <gs://bucket[/prefix]> [--skip-dates]
# 
# Examples:
#   list_bucket_folders gs://some-data/
#   list_bucket_folders gs://some-data/prefix --skip-dates

list_bucket_folders() {
    local BUCKET_PATH="$1"
    local skip_dates=false

    if [[ -z "$BUCKET_PATH" ]]; then
        echo "Usage: list_bucket_folders <gs://bucket[/prefix]> [--skip-dates]"
        echo "Example: list_bucket_folders gs://some-data/"
        return 1
    fi

    shift || true
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --skip-dates) skip_dates=true; shift ;;
            *) echo "Unknown option: $1"; return 1 ;;
        esac
    done

    # Ensure trailing slash
    [[ "$BUCKET_PATH" != */ ]] && BUCKET_PATH="$BUCKET_PATH/"

    list_directories_rec() {
        local path="$1"
        local indent="$2"
        # List directories at current path
        local directories
        directories=$(gsutil ls "$path" 2>/dev/null | grep '/$' || true)
        for dir in $directories; do
            # Skip self
            if [[ "$dir" == "$path" ]]; then
                continue
            fi
            if $skip_dates; then
                if [[ $(basename "$dir") =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}/$ ]]; then
                    continue
                fi
            fi
            echo "${indent}${dir}"
            list_directories_rec "$dir" "${indent}    "
        done
    }

    echo ""
    list_directories_rec "$BUCKET_PATH" ""
    echo ""
}

export -f list_bucket_folders

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    list_bucket_folders "$@"
fi
#!/bin/bash

# move_amp: Copy amplitude files based on date range patterns
# Usage:
#   move_amp <src_path> --start <start_date> --end <end_date> <dest_path> [--parallelism N] [--dry-run]
#
# Examples:
#   # Copy files from date range (YYYY-MM-DD format)
#   move_amp gs://bucket/path/382852/ --start 2025-08-30 --end 2025-09-29 gs://bucket/dest/
#   move_amp gs://bucket/path/382852/ --start 2025-08-30 --end 2025-09-29 gs://bucket/dest/ --parallelism 16
#   move_amp gs://bucket/path/382852/ --start 2025-08-30 --end 2025-09-29 gs://bucket/dest/ --dry-run
#
# Notes:
# - Expects amplitude files with pattern: *_YYYY-MM-DD_*.json.gz
# - Uses gsutil for GCS operations with parallel processing
# - Date range is inclusive (includes both start and end dates)

move_amp() {
    if [[ "$#" -lt 6 ]]; then
        echo "Usage: move_amp <src_path> --start <start_date> --end <end_date> <dest_path> [--parallelism N] [--dry-run]"
        echo ""
        echo "Examples:"
        echo "  move_amp gs://bucket/path/382852/ --start 2025-08-30 --end 2025-09-29 gs://bucket/dest/"
        echo "  move_amp gs://bucket/path/382852/ --start 2025-08-30 --end 2025-09-29 gs://bucket/dest/ --parallelism 16"
        echo "  move_amp gs://bucket/path/382852/ --start 2025-08-30 --end 2025-09-29 gs://bucket/dest/ --dry-run"
        echo ""
        echo "Date format: YYYY-MM-DD"
        return 1
    fi

    local src_path=""
    local dest_path=""
    local start_date=""
    local end_date=""
    local parallelism=8
    local dry_run=false

    # Parse arguments manually
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --start)
                start_date="$2"; shift 2 ;;
            --end)
                end_date="$2"; shift 2 ;;
            --parallelism)
                parallelism="$2"; shift 2 ;;
            --dry-run)
                dry_run=true; shift ;;
            -*)
                echo "Unknown option: $1"; return 1 ;;
            *)
                if [[ -z "$src_path" ]]; then
                    src_path="$1"
                elif [[ -z "$dest_path" ]]; then
                    dest_path="$1"
                else
                    echo "Error: Too many positional arguments: $1"
                    return 1
                fi
                shift ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$src_path" || -z "$dest_path" ]]; then
        echo "Error: Both source and destination paths are required"
        return 1
    fi

    if [[ -z "$start_date" || -z "$end_date" ]]; then
        echo "Error: Both --start and --end dates are required"
        return 1
    fi

    # Validate date format (basic check)
    if [[ ! "$start_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo "Error: start_date must be in YYYY-MM-DD format"
        return 1
    fi
    if [[ ! "$end_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo "Error: end_date must be in YYYY-MM-DD format"
        return 1
    fi

    # Validate cloud storage paths
    if [[ "$src_path" != gs://* && "$src_path" != s3://* ]]; then
        echo "Error: source path must be gs:// or s3://"
        return 1
    fi
    if [[ "$dest_path" != gs://* && "$dest_path" != s3://* ]]; then
        echo "Error: destination path must be gs:// or s3://"
        return 1
    fi

    # Check tool availability
    if [[ "$src_path" == gs://* ]] && ! command -v gsutil >/dev/null 2>&1; then
        echo "Error: gsutil not found. Please install Google Cloud SDK."
        return 1
    fi
    if [[ "$src_path" == s3://* ]] && ! command -v aws >/dev/null 2>&1; then
        echo "Error: aws CLI not found. Please install AWS CLI."
        return 1
    fi

    echo "🔍 Finding amplitude files in date range: $start_date to $end_date"
    echo "📂 Source: $src_path"
    echo "📁 Destination: $dest_path"
    echo "⚡ Parallelism: $parallelism"
    if $dry_run; then echo "🧪 DRY RUN MODE - No files will be copied"; fi
    echo ""

    # Create temporary file for matching files
    local temp_file=$(mktemp)
    trap "rm -f '$temp_file'" EXIT

    # Generate date range for pattern matching
    local current_date="$start_date"
    local end_date_epoch=$(date -j -f "%Y-%m-%d" "$end_date" "+%s" 2>/dev/null)
    local start_date_epoch=$(date -j -f "%Y-%m-%d" "$start_date" "+%s" 2>/dev/null)

    if [[ $? -ne 0 ]]; then
        echo "Error: Invalid date format. Please use YYYY-MM-DD"
        return 1
    fi

    echo "📋 Generating file list for date range..."
    local file_count=0

    local current_date_epoch="$start_date_epoch"
    while [[ "$current_date_epoch" -le "$end_date_epoch" ]]; do
        local pattern="${src_path}*_${current_date}_*.json.gz"

        if [[ "$src_path" == gs://* ]]; then
            # Use gsutil ls to find matching files
            gsutil ls "$pattern" 2>/dev/null >> "$temp_file" && ((file_count++))
        elif [[ "$src_path" == s3://* ]]; then
            # Use aws s3 ls with pattern matching
            local bucket_and_prefix="${pattern#s3://}"
            local bucket="${bucket_and_prefix%%/*}"
            local prefix="${bucket_and_prefix#*/}"
            prefix="${prefix%/*_${current_date}_*.json.gz}/"

            aws s3 ls "s3://$bucket/$prefix" --recursive | \
                grep "_${current_date}_.*\.json\.gz$" | \
                awk '{print "s3://'$bucket'/"$4}' >> "$temp_file" && ((file_count++))
        fi

        # Increment date
        if command -v gdate >/dev/null 2>&1; then
            # GNU date (via brew install coreutils)
            current_date=$(gdate -d "$current_date + 1 day" "+%Y-%m-%d")
            current_date_epoch=$(gdate -d "$current_date" "+%s")
        else
            # macOS date
            current_date=$(date -j -v+1d -f "%Y-%m-%d" "$current_date" "+%Y-%m-%d")
            current_date_epoch=$(date -j -f "%Y-%m-%d" "$current_date" "+%s")
        fi
    done

    # Count total files found
    local total_files=$(wc -l < "$temp_file" | tr -d ' ')

    if [[ "$total_files" -eq 0 ]]; then
        echo "❌ No files found matching date range $start_date to $end_date"
        return 1
    fi

    echo "✅ Found $total_files files to copy"

    if $dry_run; then
        echo ""
        echo "📄 Files that would be copied:"
        head -20 "$temp_file"
        if [[ "$total_files" -gt 20 ]]; then
            echo "... and $((total_files - 20)) more files"
        fi
        return 0
    fi

    echo ""
    echo "🚀 Starting parallel copy operation..."

    # Perform the copy operation
    if [[ "$src_path" == gs://* ]]; then
        # Use gsutil with parallel processing
        cat "$temp_file" | xargs -P "$parallelism" -I {} gsutil cp {} "$dest_path"
        local exit_code=$?
    elif [[ "$src_path" == s3://* ]]; then
        # Use aws s3 cp with parallel processing
        cat "$temp_file" | xargs -P "$parallelism" -I {} sh -c 'aws s3 cp "$1" "$2"' _ {} "$dest_path"
        local exit_code=$?
    fi

    if [[ $exit_code -eq 0 ]]; then
        echo ""
        echo "✅ Successfully copied $total_files amplitude files"
        echo "📁 Files copied to: $dest_path"
    else
        echo ""
        echo "❌ Copy operation failed with exit code: $exit_code"
        return $exit_code
    fi
}

export -f move_amp

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    move_amp "$@"
fi
#!/bin/bash

# Ultra-fast parallel decompression for cloud storage files
parallel_gunzip() {
    # Show help if no arguments or help requested
    if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: parallel_gunzip <source-pattern> <destination-bucket> [concurrency]"
        echo ""
        echo "Ultra-fast parallel decompression for large cloud storage files."
        echo "Optimized for processing hundreds of large .gz files efficiently."
        echo ""
        echo "Arguments:"
        echo "  source-pattern       GCS pattern for .gz files (e.g., 'gs://bucket/path/*.gz')"
        echo "  destination-bucket   Destination bucket for decompressed files"
        echo "  concurrency          Max concurrent processes (default: 8)"
        echo ""
        echo "Options:"
        echo "  --dry-run           Show what would be processed without actually doing it"
        echo "  --remove-extension  Remove specific extension (default: .gz)"
        echo "  --add-extension     Add extension to output files (e.g., .json)"
        echo ""
        echo "Examples:"
        echo "  parallel_gunzip 'gs://source/data/*.gz' gs://dest/decompressed/"
        echo "  parallel_gunzip 'gs://logs/*.json.gz' gs://processed/ --add-extension=.json"
        echo "  parallel_gunzip 'gs://backup/*.gz' gs://restored/ --dry-run"
        return 0
    fi

    local source_pattern="$1"
    local destination_bucket="$2"
    local concurrency="${3:-8}"
    local dry_run=false
    local remove_ext=".gz"
    local add_ext=""

    # Parse additional arguments
    shift 2
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                dry_run=true
                shift
                ;;
            --remove-extension=*)
                remove_ext="${1#*=}"
                shift
                ;;
            --add-extension=*)
                add_ext="${1#*=}"
                shift
                ;;
            [0-9]*)
                concurrency="$1"
                shift
                ;;
            *)
                echo "Unknown option: $1"
                return 1
                ;;
        esac
    done

    # Validate input
    if [[ ! "$source_pattern" =~ ^gs:// ]]; then
        echo "❌ Error: Source pattern must start with gs://"
        return 1
    fi

    if [[ ! "$destination_bucket" =~ ^gs:// ]]; then
        echo "❌ Error: Destination bucket must start with gs://"
        return 1
    fi

    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        echo "❌ Error: gsutil is not installed or not in PATH"
        return 1
    fi

    # Set optimal performance environment variables
    export CLOUDSDK_STORAGE_THREAD_COUNT=32
    export CLOUDSDK_STORAGE_PROCESS_COUNT=8
    export CLOUDSDK_STORAGE_PARALLEL_COMPOSITE_UPLOAD_THRESHOLD=50M
    export CLOUDSDK_STORAGE_SLICED_OBJECT_DOWNLOAD_THRESHOLD=50M
    export CLOUDSDK_STORAGE_SLICED_OBJECT_DOWNLOAD_MAX_PROCESSES=8

    echo "🚀 Ultra-Fast Batch Decompression Starting"
    echo "==========================================="
    echo "Source: $source_pattern"
    echo "Destination: $destination_bucket"
    echo "Max concurrent processes: $concurrency"
    echo "Remove extension: $remove_ext"
    if [[ -n "$add_ext" ]]; then
        echo "Add extension: $add_ext"
    fi
    if $dry_run; then
        echo "🔍 DRY RUN MODE - No files will be processed"
    fi
    echo ""

    # Get file list
    echo "📂 Scanning for files..."
    local file_list
    file_list=$(gsutil ls "$source_pattern" 2>/dev/null)

    if [[ -z "$file_list" ]]; then
        echo "❌ No files found matching: $source_pattern"
        return 1
    fi

    local total_files=$(echo "$file_list" | wc -l)
    echo "📊 Found $(printf "%'d" $total_files) files to process"

    # Estimate total size (rough calculation for .gz files)
    echo "📏 Estimating total size..."
    local estimated_size_mb=$((total_files * 500))  # Assume ~500MB average per .gz file
    echo "📊 Estimated total size: ~$(printf "%'d" $estimated_size_mb)MB compressed"
    echo ""

    if $dry_run; then
        echo "🔍 DRY RUN - Files that would be processed:"
        echo "$file_list" | while IFS= read -r file; do
            local filename=$(basename "$file")
            local output_name="${filename%$remove_ext}${add_ext}"
            echo "  $filename → $output_name"
        done
        echo ""
        echo "ℹ️  Use without --dry-run to perform actual decompression"
        return 0
    fi

    echo "⚡ Starting parallel processing..."
    echo ""

    # Create temporary directory for tracking
    local temp_dir=$(mktemp -d)
    local start_time=$(date +%s)

    # Create worker script for processing individual files
    cat > "$temp_dir/decompress_worker.sh" << 'EOF'
#!/bin/bash
decompress_file() {
    local file="$1"
    local destination_bucket="$2"
    local remove_ext="$3"
    local add_ext="$4"

    local filename=$(basename "$file")
    local output_name="${filename%$remove_ext}${add_ext}"

    local start=$(date +%s)
    echo "[$(date +%H:%M:%S)] ⚡ Starting: $filename"

    # Ultra-fast streaming with optimized settings
    if gsutil -q \
        -o "GSUtil:parallel_composite_upload_threshold=50M" \
        -o "GSUtil:sliced_object_download_threshold=50M" \
        -o "GSUtil:sliced_object_download_max_processes=4" \
        cat "$file" | gunzip -c | gsutil -q \
        -o "GSUtil:parallel_composite_upload_threshold=50M" \
        cp - "${destination_bucket}/${output_name}" 2>/dev/null
    then
        local end=$(date +%s)
        local duration=$((end - start))
        echo "[$(date +%H:%M:%S)] ✅ DONE: $output_name (${duration}s)"
        return 0
    else
        echo "[$(date +%H:%M:%S)] ❌ FAILED: $filename" >&2
        return 1
    fi
}

decompress_file "$1" "$2" "$3" "$4"
EOF

    chmod +x "$temp_dir/decompress_worker.sh"

    # Process files with maximum parallelism
    echo "$file_list" | xargs -I {} -P "$concurrency" -n 1 bash -c '"$0" "$1" "$2" "$3" "$4"' "$temp_dir/decompress_worker.sh" {} "$destination_bucket" "$remove_ext" "$add_ext"

    # Calculate final statistics
    local end_time=$(date +%s)
    local total_duration=$((end_time - start_time))
    local minutes=$((total_duration / 60))
    local seconds=$((total_duration % 60))

    echo ""
    echo "🎉 BATCH PROCESSING COMPLETE"
    echo "============================="
    echo "Total time: ${minutes}m ${seconds}s"

    if [[ $total_files -gt 0 && $total_duration -gt 0 ]]; then
        local avg_per_file=$((total_duration / total_files))
        local throughput_mb=$((estimated_size_mb / total_duration))
        echo "Average per file: ${avg_per_file}s"
        echo "Throughput: ~${throughput_mb}MB/s"
    fi

    echo ""

    # Quick verification
    echo "🔍 Verifying results..."
    local result_count=$(gsutil ls "${destination_bucket}*" 2>/dev/null | wc -l)
    echo "📊 Files created: $(printf "%'d" $result_count)/$(printf "%'d" $total_files)"

    if [[ $result_count -eq $total_files ]]; then
        echo "🎉 SUCCESS: All files processed successfully!"
    else
        echo "⚠️  WARNING: $(printf "%'d" $total_files) files processed, but only $(printf "%'d" $result_count) outputs found"
        echo ""
        echo "💡 To find missing files, run:"
        echo "comm -23 <(gsutil ls '$source_pattern' | xargs -n1 basename -s $remove_ext | sort) <(gsutil ls '${destination_bucket}*' | xargs -n1 basename -s '$add_ext' | sort)"
    fi

    echo ""

    # Cleanup
    rm -rf "$temp_dir"

    return 0
}

# Export function
export -f parallel_gunzip

# Run directly if executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parallel_gunzip "$@"
fi
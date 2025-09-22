#!/bin/bash

# Count files matching a pattern in cloud storage
count_files() {
    # Show help if no arguments or help requested
    if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: count_files <storage-pattern> [--detailed]"
        echo ""
        echo "Count files matching a pattern in cloud storage."
        echo ""
        echo "Arguments:"
        echo "  storage-pattern  GCS/S3 pattern to match files (e.g., 'gs://bucket/path/*.gz')"
        echo ""
        echo "Options:"
        echo "  --detailed       Show detailed breakdown by file extensions"
        echo "  --sizes          Show total size information"
        echo ""
        echo "Examples:"
        echo "  count_files 'gs://bucket/data/*.json'"
        echo "  count_files 'gs://logs/*.gz' --detailed"
        echo "  count_files 's3://bucket/files/*' --sizes"
        return 0
    fi

    local storage_pattern="$1"
    local detailed=false
    local show_sizes=false

    # Parse arguments
    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --detailed)
                detailed=true
                shift
                ;;
            --sizes)
                show_sizes=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                return 1
                ;;
        esac
    done

    # Validate input
    if [[ ! "$storage_pattern" =~ ^(gs|s3):// ]]; then
        echo "❌ Error: Storage pattern must start with gs:// or s3://"
        return 1
    fi

    # Check required tools
    if [[ "$storage_pattern" =~ ^gs:// ]] && ! command -v gsutil &> /dev/null; then
        echo "❌ Error: gsutil is not installed or not in PATH"
        return 1
    elif [[ "$storage_pattern" =~ ^s3:// ]] && ! command -v aws &> /dev/null; then
        echo "❌ Error: aws CLI is not installed or not in PATH"
        return 1
    fi

    echo "📊 Counting files matching: $storage_pattern"
    echo ""

    # Create temporary file for processing
    local temp_file=$(mktemp)

    # Get file list based on storage type
    if [[ "$storage_pattern" =~ ^gs:// ]]; then
        if $show_sizes; then
            gsutil ls -l "$storage_pattern" 2>/dev/null | grep -v 'TOTAL:' | awk 'NF>1 {print $3 "\t" $1}' > "$temp_file"
        else
            gsutil ls "$storage_pattern" 2>/dev/null > "$temp_file"
        fi
    elif [[ "$storage_pattern" =~ ^s3:// ]]; then
        # Handle S3 pattern
        local bucket_path="${storage_pattern#s3://}"
        local bucket="${bucket_path%%/*}"
        local prefix="${bucket_path#*/}"
        prefix="${prefix%/*}/"

        if $show_sizes; then
            aws s3 ls "s3://$bucket/$prefix" --recursive 2>/dev/null | awk '{print "s3://'$bucket'/" $4 "\t" $3}' | grep -E "${storage_pattern//\*/.*}" > "$temp_file"
        else
            aws s3 ls "s3://$bucket/$prefix" --recursive 2>/dev/null | awk '{print "s3://'$bucket'/" $4}' | grep -E "${storage_pattern//\*/.*}" > "$temp_file"
        fi
    fi

    # Check if any files were found
    if [[ ! -s "$temp_file" ]]; then
        echo "❌ No files found matching pattern: $storage_pattern"
        rm -f "$temp_file"
        return 1
    fi

    # Count total files
    local total_count=$(wc -l < "$temp_file")
    echo "📁 Total files: $(printf "%'d" $total_count)"

    # Show size information if requested
    if $show_sizes; then
        echo ""
        echo "📏 Size Information:"
        echo "==================="

        local total_bytes=0
        while IFS=$'\t' read -r file size; do
            total_bytes=$((total_bytes + size))
        done < "$temp_file"

        if command -v numfmt &> /dev/null; then
            local total_hr=$(numfmt --to=iec --suffix=B --format="%.2f" "$total_bytes")
        else
            local total_hr="${total_bytes}B"
        fi

        echo "Total size: $total_hr"

        # Show size distribution
        local min_size max_size
        min_size=$(cut -f2 "$temp_file" | sort -n | head -1)
        max_size=$(cut -f2 "$temp_file" | sort -n | tail -1)

        if command -v numfmt &> /dev/null; then
            local min_hr=$(numfmt --to=iec --suffix=B --format="%.1f" "$min_size" 2>/dev/null || echo "${min_size}B")
            local max_hr=$(numfmt --to=iec --suffix=B --format="%.1f" "$max_size" 2>/dev/null || echo "${max_size}B")
        else
            local min_hr="${min_size}B"
            local max_hr="${max_size}B"
        fi

        echo "Size range: $min_hr - $max_hr"

        if [[ $total_count -gt 0 ]]; then
            local avg_size=$((total_bytes / total_count))
            if command -v numfmt &> /dev/null; then
                local avg_hr=$(numfmt --to=iec --suffix=B --format="%.1f" "$avg_size" 2>/dev/null || echo "${avg_size}B")
            else
                local avg_hr="${avg_size}B"
            fi
            echo "Average size: $avg_hr"
        fi
    fi

    # Show detailed breakdown if requested
    if $detailed; then
        echo ""
        echo "📊 File Extensions Breakdown:"
        echo "============================="

        # Extract extensions and count them
        if $show_sizes; then
            cut -f1 "$temp_file"
        else
            cat "$temp_file"
        fi | while read -r file; do
            local basename_file=$(basename "$file")
            if [[ "$basename_file" == *.* ]]; then
                echo "${basename_file##*.}"
            else
                echo "no-extension"
            fi
        done | sort | uniq -c | sort -nr | while read -r count ext; do
            printf "%8s files with .%s extension\n" "$(printf "%'d" $count)" "$ext"
        done

        echo ""
        echo "📂 Directory Distribution:"
        echo "========================="

        # Count files per directory
        if $show_sizes; then
            cut -f1 "$temp_file"
        else
            cat "$temp_file"
        fi | while read -r file; do
            dirname "$file"
        done | sort | uniq -c | sort -nr | head -10 | while read -r count dir; do
            printf "%8s files in %s\n" "$(printf "%'d" $count)" "$dir"
        done
    fi

    echo ""

    # Show sample files
    echo "📄 Sample files:"
    echo "==============="

    if $show_sizes; then
        head -5 "$temp_file" | while IFS=$'\t' read -r file size; do
            if command -v numfmt &> /dev/null; then
                local size_hr=$(numfmt --to=iec --suffix=B --format="%.1f" "$size" 2>/dev/null || echo "${size}B")
            else
                local size_hr="${size}B"
            fi
            printf "  %s (%s)\n" "$(basename "$file")" "$size_hr"
        done
    else
        head -5 "$temp_file" | while read -r file; do
            printf "  %s\n" "$(basename "$file")"
        done
    fi

    if [[ $total_count -gt 5 ]]; then
        echo "  ... and $((total_count - 5)) more files"
    fi

    echo ""

    # Cleanup
    rm -f "$temp_file"

    return 0
}

# Export function
export -f count_files

# Run directly if executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    count_files "$@"
fi
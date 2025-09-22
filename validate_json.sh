#!/bin/bash

# Validate JSON files in cloud storage with parallel processing
validate_json() {
    # Show help if no arguments or help requested
    if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: validate_json <source-pattern> [concurrency] [--sample=N]"
        echo ""
        echo "Validate JSON files in cloud storage with parallel processing."
        echo ""
        echo "Arguments:"
        echo "  source-pattern   GCS pattern for JSON files (e.g., 'gs://bucket/path/*.json')"
        echo "  concurrency      Number of parallel validations (default: 8)"
        echo ""
        echo "Options:"
        echo "  --sample=N       Only validate N random files (for quick checks)"
        echo "  --detailed       Show detailed error messages for invalid JSON"
        echo "  --stats          Show JSON structure statistics"
        echo ""
        echo "Examples:"
        echo "  validate_json 'gs://bucket/data/*.json'"
        echo "  validate_json 'gs://logs/*.json' 8 --sample=100"
        echo "  validate_json 'gs://files/*.json' --detailed --stats"
        return 0
    fi

    local source_pattern="$1"
    local concurrency="${2:-8}"
    local sample_size=""
    local detailed=false
    local show_stats=false

    # Parse arguments
    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --sample=*)
                sample_size="${1#*=}"
                shift
                ;;
            --detailed)
                detailed=true
                shift
                ;;
            --stats)
                show_stats=true
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

    # Check required tools
    if ! command -v gsutil &> /dev/null; then
        echo "❌ Error: gsutil is not installed or not in PATH"
        return 1
    fi

    if ! command -v jq &> /dev/null; then
        echo "❌ Error: jq is not installed or not in PATH"
        echo "Install with: brew install jq (macOS) or apt-get install jq (Ubuntu)"
        return 1
    fi

    echo "🔍 JSON Validation Starting"
    echo "============================"
    echo "Source: $source_pattern"
    echo "Concurrency: $concurrency"
    if [[ -n "$sample_size" ]]; then
        echo "Sample size: $sample_size files"
    fi
    echo ""

    # Get file list
    echo "📂 Scanning for JSON files..."
    local file_list
    file_list=$(gsutil ls "$source_pattern" 2>/dev/null)

    if [[ -z "$file_list" ]]; then
        echo "❌ No files found matching: $source_pattern"
        return 1
    fi

    local total_files=$(echo "$file_list" | wc -l)
    echo "📊 Found $(printf "%'d" $total_files) JSON files"

    # Sample files if requested
    if [[ -n "$sample_size" ]]; then
        if [[ $sample_size -lt $total_files ]]; then
            file_list=$(echo "$file_list" | shuf -n "$sample_size")
            total_files=$sample_size
            echo "🎲 Randomly sampled $(printf "%'d" $sample_size) files"
        fi
    fi

    echo ""

    # Create temporary directory
    local temp_dir=$(mktemp -d)
    local results_file="$temp_dir/results.txt"
    local errors_file="$temp_dir/errors.txt"
    local stats_file="$temp_dir/stats.txt"

    # Create validation worker
    cat > "$temp_dir/validate_worker.sh" << 'EOF'
#!/bin/bash
validate_single_json() {
    local file="$1"
    local results_file="$2"
    local errors_file="$3"
    local stats_file="$4"
    local detailed="$5"
    local show_stats="$6"

    local filename=$(basename "$file")
    echo "🔍 Validating: $filename" >&2

    # Download and validate JSON
    local temp_json=$(mktemp)
    if gsutil cat "$file" > "$temp_json" 2>/dev/null; then
        # Validate JSON syntax
        if jq . "$temp_json" > /dev/null 2>/dev/null; then
            echo -e "VALID\t$file\tOK" >> "$results_file"

            # Collect stats if requested
            if [[ "$show_stats" == "true" ]]; then
                local line_count=$(wc -l < "$temp_json")
                local size_bytes=$(stat -f%z "$temp_json" 2>/dev/null || stat -c%s "$temp_json" 2>/dev/null || echo "0")
                local type=$(jq -r 'type' "$temp_json" 2>/dev/null || echo "unknown")

                echo -e "$file\t$line_count\t$size_bytes\t$type" >> "$stats_file"
            fi

            echo "    ✅ Valid JSON" >&2
        else
            # Invalid JSON
            local error_msg="Invalid JSON syntax"
            if [[ "$detailed" == "true" ]]; then
                error_msg=$(jq . "$temp_json" 2>&1 | head -1)
            fi

            echo -e "INVALID\t$file\t$error_msg" >> "$errors_file"
            echo "    ❌ Invalid JSON: $error_msg" >&2
        fi
    else
        echo -e "ERROR\t$file\tFailed to download" >> "$errors_file"
        echo "    ❌ Download failed" >&2
    fi

    rm -f "$temp_json"
}

validate_single_json "$1" "$2" "$3" "$4" "$5" "$6"
EOF

    chmod +x "$temp_dir/validate_worker.sh"

    echo "⚡ Starting parallel validation..."
    local start_time=$(date +%s)

    # Process files in parallel
    echo "$file_list" | xargs -I {} -P "$concurrency" -n 1 bash -c '"$0" "$1" "$2" "$3" "$4" "$5" "$6"' \
        "$temp_dir/validate_worker.sh" {} "$results_file" "$errors_file" "$stats_file" "$detailed" "$show_stats"

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    echo ""
    echo "📊 Validation Results"
    echo "===================="

    # Count results
    local valid_count=0
    local invalid_count=0
    local error_count=0

    if [[ -f "$results_file" ]]; then
        valid_count=$(wc -l < "$results_file")
    fi

    if [[ -f "$errors_file" ]]; then
        while IFS=$'\t' read -r status file message; do
            if [[ "$status" == "INVALID" ]]; then
                ((invalid_count++))
            elif [[ "$status" == "ERROR" ]]; then
                ((error_count++))
            fi
        done < "$errors_file"
    fi

    echo "✅ Valid JSON files: $(printf "%'d" $valid_count)"
    echo "❌ Invalid JSON files: $(printf "%'d" $invalid_count)"
    if [[ $error_count -gt 0 ]]; then
        echo "⚠️  Download errors: $(printf "%'d" $error_count)"
    fi

    local success_rate=0
    if [[ $total_files -gt 0 ]]; then
        success_rate=$(( (valid_count * 100) / total_files ))
    fi
    echo "📈 Success rate: ${success_rate}%"
    echo "⏱️  Processing time: ${duration}s"

    # Show detailed errors if any
    if [[ $invalid_count -gt 0 || $error_count -gt 0 ]]; then
        echo ""
        echo "❌ Issues Found:"
        echo "==============="

        if [[ -f "$errors_file" ]]; then
            while IFS=$'\t' read -r status file message; do
                echo "$(basename "$file"): $message"
            done < "$errors_file"
        fi
    fi

    # Show statistics if requested
    if $show_stats && [[ -f "$stats_file" ]]; then
        echo ""
        echo "📊 JSON Statistics"
        echo "=================="

        echo "File size distribution:"
        awk -F'\t' '{print $3}' "$stats_file" | sort -n | awk '
            {sizes[NR]=$1; sum+=$1}
            END {
                printf "   Min: %d bytes\n", sizes[1]
                printf "   Max: %d bytes\n", sizes[NR]
                printf "   Avg: %d bytes\n", sum/NR
                printf "   Median: %d bytes\n", sizes[int(NR/2)]
            }'

        echo ""
        echo "JSON types:"
        awk -F'\t' '{print $4}' "$stats_file" | sort | uniq -c | sort -nr | while read -r count type; do
            printf "   %s: %d files\n" "$type" "$count"
        done
    fi

    echo ""

    # Cleanup
    rm -rf "$temp_dir"

    return 0
}

# Export function
export -f validate_json

# Run directly if executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    validate_json "$@"
fi
#!/bin/bash

# Bulk rename files in cloud storage with parallel processing
rename_files() {
    # Show help if no arguments or help requested
    if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: rename_files <source-pattern> <operation> [concurrency]"
        echo ""
        echo "Bulk rename files in cloud storage with parallel processing."
        echo ""
        echo "Arguments:"
        echo "  source-pattern   GCS pattern to match files (e.g., 'gs://bucket/path/*')"
        echo "  operation        Rename operation type:"
        echo "                   'add-extension:EXT' - Add extension to files"
        echo "                   'remove-extension:EXT' - Remove specific extension"
        echo "                   'replace:OLD:NEW' - Replace text in filenames"
        echo "                   'prefix:TEXT' - Add prefix to filenames"
        echo "                   'suffix:TEXT' - Add suffix before extension"
        echo "  concurrency      Number of parallel operations (default: 10)"
        echo ""
        echo "Examples:"
        echo "  rename_files 'gs://bucket/files/*' 'add-extension:.json.gz'"
        echo "  rename_files 'gs://bucket/*.tmp' 'remove-extension:.tmp'"
        echo "  rename_files 'gs://bucket/old_*' 'replace:old_:new_'"
        echo "  rename_files 'gs://bucket/data/*' 'prefix:processed_'"
        echo "  rename_files 'gs://bucket/*.log' 'suffix:_backup'"
        return 0
    fi

    local source_pattern="$1"
    local operation="$2"
    local concurrency="${3:-8}"

    # Validate input
    if [[ -z "$source_pattern" || -z "$operation" ]]; then
        echo "Error: Both source pattern and operation are required"
        return 1
    fi

    if [[ ! "$source_pattern" =~ ^gs:// ]]; then
        echo "Error: Source pattern must start with gs://"
        return 1
    fi

    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        echo "Error: gsutil is not installed or not in PATH"
        return 1
    fi

    echo "🔄 Starting bulk rename operation"
    echo "Source pattern: $source_pattern"
    echo "Operation: $operation"
    echo "Concurrency: $concurrency"
    echo ""

    # Get list of files
    local files
    files=$(gsutil ls "$source_pattern" 2>/dev/null)

    if [[ -z "$files" ]]; then
        echo "❌ No files found matching: $source_pattern"
        return 1
    fi

    local file_count=$(echo "$files" | wc -l)
    echo "📊 Found $(printf "%'d" $file_count) files to process"
    echo ""

    # Create temporary directory for tracking
    local temp_dir=$(mktemp -d)
    local results_file="$temp_dir/results.txt"
    local errors_file="$temp_dir/errors.txt"

    # Create rename function based on operation type
    cat > "$temp_dir/rename_worker.sh" << 'EOF'
#!/bin/bash
rename_single_file() {
    local file="$1"
    local operation="$2"
    local results_file="$3"
    local errors_file="$4"

    local basename_file=$(basename "$file")
    local dirname_file=$(dirname "$file")
    local new_name=""

    # Parse operation
    local op_type="${operation%%:*}"
    local op_params="${operation#*:}"

    case "$op_type" in
        "add-extension")
            new_name="${basename_file}${op_params}"
            ;;
        "remove-extension")
            if [[ "$basename_file" == *"$op_params" ]]; then
                new_name="${basename_file%$op_params}"
            else
                echo "⚠️  File $basename_file does not have extension $op_params" >&2
                return 0
            fi
            ;;
        "replace")
            local old_text="${op_params%%:*}"
            local new_text="${op_params#*:}"
            new_name="${basename_file//$old_text/$new_text}"
            ;;
        "prefix")
            new_name="${op_params}${basename_file}"
            ;;
        "suffix")
            if [[ "$basename_file" == *.* ]]; then
                local name_part="${basename_file%.*}"
                local ext_part="${basename_file##*.}"
                new_name="${name_part}${op_params}.${ext_part}"
            else
                new_name="${basename_file}${op_params}"
            fi
            ;;
        *)
            echo "❌ Unknown operation: $op_type" >&2
            return 1
            ;;
    esac

    # Skip if name hasn't changed
    if [[ "$basename_file" == "$new_name" ]]; then
        echo "⚠️  No change needed: $basename_file" >&2
        return 0
    fi

    local new_path="${dirname_file}/${new_name}"

    echo "🔄 Renaming: $(basename "$file") → $new_name" >&2

    # Perform the rename
    if gsutil mv "$file" "$new_path" 2>/dev/null; then
        echo -e "SUCCESS\t$file\t$new_path" >> "$results_file"
        echo "✅ Renamed: $(basename "$file") → $new_name" >&2
    else
        echo -e "ERROR\t$file\tFailed to rename" >> "$errors_file"
        echo "❌ Failed: $(basename "$file")" >&2
    fi
}

rename_single_file "$1" "$2" "$3" "$4"
EOF

    chmod +x "$temp_dir/rename_worker.sh"

    echo "🚀 Starting parallel rename operations..."
    echo ""

    # Process files in parallel
    echo "$files" | xargs -I {} -P "$concurrency" -n 1 "$temp_dir/rename_worker.sh" {} "$operation" "$results_file" "$errors_file"

    # Wait for all processes to complete
    wait

    echo ""
    echo "📋 Results Summary:"
    echo "=================="

    # Count results
    local success_count=0
    local error_count=0

    if [[ -f "$results_file" ]]; then
        success_count=$(wc -l < "$results_file")
    fi

    if [[ -f "$errors_file" ]]; then
        error_count=$(wc -l < "$errors_file")
    fi

    echo "✅ Successfully renamed: $success_count files"

    if [[ $error_count -gt 0 ]]; then
        echo "❌ Failed to rename: $error_count files"
        echo ""
        echo "Failed files:"
        while IFS=$'\t' read -r status file reason; do
            echo "  - $(basename "$file"): $reason"
        done < "$errors_file"
    fi

    echo ""
    echo "🎉 Bulk rename operation completed!"

    # Cleanup
    rm -rf "$temp_dir"

    return 0
}

# Export function
export -f rename_files

# Run directly if executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    rename_files "$@"
fi
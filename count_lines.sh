#!/bin/bash

# Function to count lines in cloud storage files with wildcards
count_lines() {
    local storage_path="$1"
    local concurrency="${2:-8}"
    local temp_dir=$(mktemp -d)
    local results_file="$temp_dir/results.txt"
    
    # Validate input
    if [[ -z "$storage_path" ]]; then
        echo "Usage: count_lines <storage_path> [concurrency]"
        echo "Example: count_lines 'gs://bucket/path/*.txt' 8"
        return 1
    fi
    
    # Detect storage type and set appropriate commands
    local list_cmd=""
    local cat_cmd=""
    
    if [[ "$storage_path" =~ ^gs:// ]]; then
        list_cmd="gsutil ls"
        cat_cmd="gsutil cat"
    elif [[ "$storage_path" =~ ^s3:// ]]; then
        list_cmd="aws s3 ls"
        cat_cmd="aws s3 cp"
    elif [[ "$storage_path" =~ ^az:// || "$storage_path" =~ ^https://.*\.blob\.core\.windows\.net ]]; then
        list_cmd="az storage blob list"
        cat_cmd="az storage blob download"
        echo "Warning: Azure Blob Storage support is basic. Consider using azcopy for better performance."
    else
        echo "Error: Unsupported storage type. Supports: gs:// (Google Cloud), s3:// (AWS S3)"
        return 1
    fi
    
    # Check if required tools are available
    if [[ "$storage_path" =~ ^gs:// ]] && ! command -v gsutil &> /dev/null; then
        echo "Error: gsutil is not installed or not in PATH"
        return 1
    elif [[ "$storage_path" =~ ^s3:// ]] && ! command -v aws &> /dev/null; then
        echo "Error: aws CLI is not installed or not in PATH"
        return 1
    fi
    
    # Create worker function for processing individual files
    cat > "$temp_dir/worker.sh" << 'EOF'
#!/bin/bash
process_file() {
    local file="$1"
    local cat_cmd="$2"
    local results_file="$3"
    
    # Handle different storage types
    local count=0
    if [[ "$file" =~ ^gs:// ]]; then
        count=$(gsutil cat "$file" 2>/dev/null | wc -l)
    elif [[ "$file" =~ ^s3:// ]]; then
        count=$(aws s3 cp "$file" - 2>/dev/null | wc -l)
    fi
    
    local exit_code=$?
    
    # Simple file locking using lockfile creation (works on macOS)
    local lock_file="$results_file.lock"
    local max_attempts=100
    local attempt=0
    
    # Try to acquire lock
    while ! mkdir "$lock_file" 2>/dev/null; do
        sleep 0.01
        ((attempt++))
        if [[ $attempt -gt $max_attempts ]]; then
            echo "Warning: Could not acquire lock for $file" >&2
            break
        fi
    done
    
    # Write results
    if [[ $exit_code -eq 0 ]]; then
        echo -e "$count\t$file" >> "$results_file"
    else
        echo -e "ERROR\t$file" >> "$results_file"
    fi
    
    # Release lock
    rmdir "$lock_file" 2>/dev/null
}

process_file "$1" "$2" "$3"
EOF
    
    chmod +x "$temp_dir/worker.sh"
    
    echo "START"
    echo "Listing files from: $storage_path"
    echo "Concurrency: $concurrency"
    echo ""
    
    # Get list of files
    local files
    if [[ "$storage_path" =~ ^gs:// ]]; then
        files=$(gsutil ls "$storage_path" 2>/dev/null)
    elif [[ "$storage_path" =~ ^s3:// ]]; then
        # For S3, we need to handle wildcards differently
        local bucket_path="${storage_path#s3://}"
        local bucket="${bucket_path%%/*}"
        local prefix="${bucket_path#*/}"
        prefix="${prefix%/*}/"  # Remove wildcard part and keep directory structure
        files=$(aws s3 ls "s3://$bucket/$prefix" --recursive 2>/dev/null | awk '{print "s3://'$bucket'/" $4}' | grep -E "${storage_path//\*/.*}")
    fi
    
    if [[ -z "$files" ]]; then
        echo "No files found matching: $storage_path"
        rm -rf "$temp_dir"
        return 1
    fi
    
    local file_count=$(echo "$files" | wc -l)
    echo "Found $file_count files to process"
    echo ""
    
    # Process files concurrently
    echo "$files" | xargs -I {} -P "$concurrency" -n 1 "$temp_dir/worker.sh" {} "$cat_cmd" "$results_file"
    
    # Wait for all background processes to complete
    wait
    
    # Check if results file exists and has content
    if [[ ! -f "$results_file" ]] || [[ ! -s "$results_file" ]]; then
        echo "Error: No results generated. Check file paths and permissions."
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Sort results by filename and display
    echo "Results:"
    echo "Lines\tFile"
    echo "-----\t----"
    
    local total_lines=0
    local processed_files=0
    local error_files=0
    
    # Process results and calculate totals
    while IFS=$'\t' read -r count file; do
        echo -e "$count\t$file"
        if [[ "$count" != "ERROR" ]]; then
            total_lines=$((total_lines + count))
            processed_files=$((processed_files + 1))
        else
            error_files=$((error_files + 1))
        fi
    done < <(sort -k2 "$results_file")
    
    echo ""
    echo "Summary:"
    echo "--------"
    echo "Total lines: $(printf "%'d" $total_lines)"
    echo "Files processed: $processed_files"
    if [[ $error_files -gt 0 ]]; then
        echo "Files with errors: $error_files"
    fi
    echo ""
    echo "DONE"
    
    # Cleanup
    rm -rf "$temp_dir"
    
    # Return the total count for potential scripting use
    return 0
}

# Make the function available for export
export -f count_lines

# If script is run directly (not sourced), execute with provided arguments
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    count_lines "$@"
fi
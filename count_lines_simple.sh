#!/bin/bash

# Simplified version for macOS - no file locking (for better performance)
count_lines_simple() {
    local storage_path="$1"
    local concurrency="${2:-8}"
    local temp_dir=$(mktemp -d)
    local results_file="$temp_dir/results.txt"
    
    # Validate input
    if [[ -z "$storage_path" ]]; then
        echo "Usage: count_lines_simple <storage_path> [concurrency]"
        echo "Example: count_lines_simple 'gs://bucket/path/*.txt' 8"
        return 1
    fi
    
    # Check if gsutil is available (simplified to focus on GCS)
    if [[ "$storage_path" =~ ^gs:// ]] && ! command -v gsutil &> /dev/null; then
        echo "Error: gsutil is not installed or not in PATH"
        return 1
    fi
    
    echo "START"
    echo "Listing files from: $storage_path"
    echo "Concurrency: $concurrency"
    echo ""
    
    # Get list of files
    local files=$(gsutil ls "$storage_path" 2>/dev/null)
    
    if [[ -z "$files" ]]; then
        echo "No files found matching: $storage_path"
        rm -rf "$temp_dir"
        return 1
    fi
    
    local file_count=$(echo "$files" | wc -l)
    echo "Found $(printf "%'d" $file_count) files to process"
    echo ""
    
    # Simple worker function that writes directly (no locking)
    process_file() {
        local file="$1"
        local results_file="$2"
        local count=$(gsutil cat "$file" 2>/dev/null | wc -l)
        local exit_code=$?
        
        if [[ $exit_code -eq 0 ]]; then
            echo -e "$count\t$file" >> "$results_file"
        else
            echo -e "ERROR\t$file" >> "$results_file"
        fi
    }
    
    export -f process_file
    
    # Process files concurrently using xargs (like your original approach)
    echo "$files" | xargs -I {} -P "$concurrency" -n 1 bash -c 'process_file() { local file="$1"; local results_file="$2"; local count=$(gsutil cat "$file" 2>/dev/null | wc -l); local exit_code=$?; if [[ $exit_code -eq 0 ]]; then echo -e "$count\t$file" >> "$results_file"; else echo -e "ERROR\t$file" >> "$results_file"; fi; }; process_file "$0" "'"$results_file"'"' {}
    
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
    echo -e "Lines\tFile"
    echo -e "-----\t----"
    
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
    
    return 0
}

# Make the function available for export
export -f count_lines_simple

# If script is run directly (not sourced), execute with provided arguments
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    count_lines_simple "$@"
fi
#!/bin/bash

# Function to find exact string matches in cloud storage files
find_matching_string() {
    local storage_path="$1"
    local search_string="$2"
    local concurrency="${3:-8}"
    local temp_dir=$(mktemp -d)
    local found_file="$temp_dir/found.txt"
    local stop_file="$temp_dir/stop"
    
    # Validate input
    if [[ -z "$storage_path" || -z "$search_string" ]]; then
        echo "Usage: find_matching_string <storage_path> <search_string> [concurrency]"
        echo "Example: find_matching_string 'gs://bucket/path/*.txt' 'needle_text' 8"
        echo ""
        echo "Searches cloud storage files for exact string matches."
        echo "Returns the first match found with filename and line number."
        return 1
    fi
    
    # Detect storage type
    local list_cmd=""
    local cat_cmd=""
    
    if [[ "$storage_path" =~ ^gs:// ]]; then
        if ! command -v gsutil &> /dev/null; then
            echo "Error: gsutil is not installed or not in PATH"
            return 1
        fi
        list_cmd="gsutil ls"
        cat_cmd="gsutil cat"
    elif [[ "$storage_path" =~ ^s3:// ]]; then
        if ! command -v aws &> /dev/null; then
            echo "Error: aws CLI is not installed or not in PATH"
            return 1
        fi
        list_cmd="aws s3 ls"
        cat_cmd="aws s3 cp"
    else
        echo "Error: Unsupported storage type. Supports: gs:// (Google Cloud), s3:// (AWS S3)"
        return 1
    fi
    
    echo "START SEARCH"
    echo "Searching in: $storage_path"
    echo "Looking for: '$search_string'"
    echo "Concurrency: $concurrency"
    echo ""
    
    # Get list of files
    local files
    if [[ "$storage_path" =~ ^gs:// ]]; then
        files=$(gsutil ls "$storage_path" 2>/dev/null)
    elif [[ "$storage_path" =~ ^s3:// ]]; then
        # Handle S3 wildcards
        local bucket_path="${storage_path#s3://}"
        local bucket="${bucket_path%%/*}"
        local prefix="${bucket_path#*/}"
        prefix="${prefix%/*}/"
        files=$(aws s3 ls "s3://$bucket/$prefix" --recursive 2>/dev/null | awk '{print "s3://'$bucket'/" $4}' | grep -E "${storage_path//\*/.*}")
    fi
    
    if [[ -z "$files" ]]; then
        echo "No files found matching: $storage_path"
        rm -rf "$temp_dir"
        return 1
    fi
    
    local file_count=$(echo "$files" | wc -l)
    echo "Found $(printf "%'d" $file_count) files to search"
    echo ""
    
    # Create worker script for searching individual files
    cat > "$temp_dir/search_worker.sh" << 'EOF'
#!/bin/bash
search_in_file() {
    local file="$1"
    local search_string="$2"
    local found_file="$3"
    local stop_file="$4"
    
    # Check if another worker already found a match
    if [[ -f "$stop_file" ]]; then
        return 0
    fi
    
    local line_number=0
    local found=false
    
    # Stream the file and search line by line
    if [[ "$file" =~ ^gs:// ]]; then
        while IFS= read -r line; do
            ((line_number++))
            
            # Check for stop signal every few lines for efficiency
            if [[ $((line_number % 1000)) -eq 0 ]] && [[ -f "$stop_file" ]]; then
                return 0
            fi
            
            # Check for exact string match
            if [[ "$line" == *"$search_string"* ]]; then
                # Try to be the first to write the result
                if ! [[ -f "$stop_file" ]]; then
                    echo "FOUND" > "$stop_file" 2>/dev/null
                    if [[ $? -eq 0 ]]; then
                        echo -e "$file\t$line_number\t$line" > "$found_file"
                        echo "✓ Match found in: $file (line $line_number)" >&2
                        return 0
                    fi
                fi
                return 0
            fi
        done < <(gsutil cat "$file" 2>/dev/null)
    elif [[ "$file" =~ ^s3:// ]]; then
        while IFS= read -r line; do
            ((line_number++))
            
            # Check for stop signal every few lines
            if [[ $((line_number % 1000)) -eq 0 ]] && [[ -f "$stop_file" ]]; then
                return 0
            fi
            
            # Check for exact string match
            if [[ "$line" == *"$search_string"* ]]; then
                # Try to be the first to write the result
                if ! [[ -f "$stop_file" ]]; then
                    echo "FOUND" > "$stop_file" 2>/dev/null
                    if [[ $? -eq 0 ]]; then
                        echo -e "$file\t$line_number\t$line" > "$found_file"
                        echo "✓ Match found in: $file (line $line_number)" >&2
                        return 0
                    fi
                fi
                return 0
            fi
        done < <(aws s3 cp "$file" - 2>/dev/null)
    fi
    
    # Indicate this file was processed (for progress tracking)
    echo "Searched: $(basename "$file")" >&2
}

search_in_file "$1" "$2" "$3" "$4"
EOF
    
    chmod +x "$temp_dir/search_worker.sh"
    
    # Start timestamp for progress tracking
    local start_time=$(date +%s)
    local files_processed=0
    
    echo "Searching files (will stop at first match)..."
    echo ""
    
    # Process files concurrently, but stop when first match is found
    echo "$files" | head -n 50 | xargs -I {} -P "$concurrency" -n 1 bash -c '
        if [[ ! -f "'$stop_file'" ]]; then
            "'$temp_dir'/search_worker.sh" "$0" "'"$search_string"'" "'"$found_file"'" "'"$stop_file"'"
        fi
    ' {} &
    
    # Monitor progress and wait for completion or match
    local batch_size=50
    local total_batches=$(((file_count + batch_size - 1) / batch_size))
    local current_batch=1
    
    echo "$files" | while IFS= read -r file; do
        # Process in batches to avoid overwhelming the system
        if [[ $((current_batch * batch_size)) -lt $files_processed ]]; then
            ((current_batch++))
            if [[ ! -f "$stop_file" ]]; then
                echo "$files" | sed -n "$((current_batch * batch_size + 1)),$((current_batch * batch_size + batch_size))p" | \
                xargs -I {} -P "$concurrency" -n 1 bash -c '
                    if [[ ! -f "'$stop_file'" ]]; then
                        "'$temp_dir'/search_worker.sh" "$0" "'"$search_string"'" "'"$found_file"'" "'"$stop_file"'"
                    fi
                ' {} &
            fi
        fi
        
        # Check if we found something
        if [[ -f "$stop_file" ]]; then
            break
        fi
        
        ((files_processed++))
        
        # Show progress every 10 files
        if [[ $((files_processed % 10)) -eq 0 ]]; then
            echo -n "." >&2
        fi
    done
    
    # Wait a bit for all processes to finish
    sleep 2
    
    # Kill any remaining background processes
    jobs -p | xargs kill 2>/dev/null
    wait 2>/dev/null
    
    echo ""
    echo ""
    
    # Check results
    if [[ -f "$found_file" ]] && [[ -s "$found_file" ]]; then
        echo "🎯 MATCH FOUND!"
        echo "=============="
        
        local result_file result_line result_content
        IFS=$'\t' read -r result_file result_line result_content < "$found_file"
        
        echo "File: $result_file"
        echo "Line: $result_line"
        echo "Content: $result_content"
        echo ""
        
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        echo "Search completed in ${duration}s"
        echo ""
        echo "FOUND"
    else
        echo "❌ NO MATCH FOUND"
        echo "=================="
        echo "Searched through available files but no exact match for '$search_string' was found."
        echo ""
        
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        echo "Search completed in ${duration}s"
        echo ""
        echo "NOT FOUND"
    fi
    
    # Cleanup
    rm -rf "$temp_dir"
    
    return 0
}

# Make the function available for export
export -f find_matching_string

# If script is run directly (not sourced), execute with provided arguments
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    find_matching_string "$@"
fi
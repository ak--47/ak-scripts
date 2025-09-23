#!/bin/bash

# Simplified cloud storage string finder - stops at first match
find_string() {
    local storage_path="$1"
    local search_string="$2"
    local concurrency="${3:-8}"
    local temp_dir=$(mktemp -d)
    local result_file="$temp_dir/result.txt"
    
    # Validate input
    if [[ -z "$storage_path" || -z "$search_string" ]]; then
        echo "Usage: find_string <storage_path> <search_string> [concurrency]"
        echo "Example: find_string 'gs://bucket/path/*.txt' 'search_text' 8"
        echo ""
        echo "Finds first exact string match in cloud storage files."
        return 1
    fi
    
    # Check gsutil availability
    if [[ "$storage_path" =~ ^gs:// ]] && ! command -v gsutil &> /dev/null; then
        echo "Error: gsutil is not installed or not in PATH"
        return 1
    fi
    
    echo "🔍 SEARCHING FOR: '$search_string'"
    echo "📁 IN PATH: $storage_path"
    echo "⚡ CONCURRENCY: $concurrency"
    echo ""
    
    # Get file list
    local files=$(gsutil ls "$storage_path" 2>/dev/null)
    if [[ -z "$files" ]]; then
        echo "❌ No files found matching: $storage_path"
        rm -rf "$temp_dir"
        return 1
    fi
    
    local file_count=$(echo "$files" | wc -l)
    echo "📊 Found $(printf "%'d" $file_count) files to search"
    echo ""
    
    
    # Start the search with limited concurrency
    echo "🚀 Starting search..."
    echo ""
    
    # Create a simple worker script
    local worker_script="$temp_dir/worker.sh"
    cat > "$worker_script" << 'EOF'
#!/bin/bash
search_single_file() {
    local file="$1"
    local search_string="$2"
    local result_file="$3"

    echo "🔍 Searching: $(basename "$file")" >&2

    local line_number=0
    while IFS= read -r line; do
        ((line_number++))

        if [[ "$line" == *"$search_string"* ]]; then
            # Found it! Write result and signal success
            {
                echo "MATCH_FOUND"
                echo "FILE: $file"
                echo "LINE: $line_number"
                echo "CONTENT: $line"
            } > "$result_file"

            echo "🎯 FOUND MATCH in $(basename "$file") at line $line_number!" >&2
            return 0
        fi
    done < <(gsutil cat "$file" 2>/dev/null)

    echo "   ❌ No match in $(basename "$file")" >&2
}

search_single_file "$1" "$2" "$3"
EOF

    chmod +x "$worker_script"

    # Use the worker script with xargs
    echo "$files" | xargs -I {} -P "$concurrency" "$worker_script" {} "$search_string" "$result_file"
    
    # Wait for results with timeout
    local timeout_seconds=3600  # 60 minute timeout
    local waited=0
    
    while [[ $waited -lt $timeout_seconds ]]; do
        if [[ -f "$result_file" ]] && grep -q "MATCH_FOUND" "$result_file" 2>/dev/null; then
            break
        fi
        sleep 1
        ((waited++))
        
        # Show progress dots
        if [[ $((waited % 5)) -eq 0 ]]; then
            echo -n "." >&2
        fi
    done
    
    # Wait for all background processes to complete
    wait 2>/dev/null
    
    echo ""
    echo ""
    
    # Check results
    if [[ -f "$result_file" ]] && grep -q "MATCH_FOUND" "$result_file" 2>/dev/null; then
        echo "🎉 SUCCESS! MATCH FOUND!"
        echo "========================="
        
        local file_path=$(grep "^FILE:" "$result_file" | cut -d' ' -f2-)
        local line_num=$(grep "^LINE:" "$result_file" | cut -d' ' -f2-)
        local content=$(grep "^CONTENT:" "$result_file" | cut -d' ' -f2-)
        
        echo "📄 File: $file_path"
        echo "📍 Line: $line_num"
        echo "💬 Content: $content"
        echo ""
        echo "✅ Search completed successfully in ${waited}s"
        
        # Cleanup
        rm -rf "$temp_dir"
        return 0
    else
        echo "❌ NO MATCH FOUND"
        echo "=================="
        echo "Searched through files but no match for '$search_string' was found."
        echo ""
        echo "⏱️  Search completed in ${waited}s"
        
        # Cleanup
        rm -rf "$temp_dir"
        return 1
    fi
}

# Export function
export -f find_string

# Run directly if executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    find_string "$@"
fi
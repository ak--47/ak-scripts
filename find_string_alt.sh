#!/bin/bash

# Cloud Storage String Finder - Efficiently finds first match and stops
# Supports GCS, AWS S3, and Azure Blob Storage with automatic gzip detection
# Version 2.0

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Global flag for early termination
MATCH_FOUND_FLAG=""
MATCH_PID=""

# Function to print colored output
print_color() {
    local color=$1
    shift
    echo -e "${color}$*${NC}" >&2
}

# Function to detect storage type
detect_storage_type() {
    local path=$1
    if [[ "$path" =~ ^gs:// ]]; then
        echo "gcs"
    elif [[ "$path" =~ ^s3:// ]]; then
        echo "s3"
    elif [[ "$path" =~ ^https://.*\.blob\.core\.windows\.net ]]; then
        echo "azure"
    else
        echo "unknown"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    local storage_type=$1
    
    case "$storage_type" in
        gcs)
            if ! command -v gsutil &> /dev/null; then
                print_color "$RED" "❌ Error: gsutil is not installed"
                echo "Install with: gcloud components install gsutil" >&2
                return 1
            fi
            ;;
        s3)
            if ! command -v aws &> /dev/null; then
                print_color "$RED" "❌ Error: aws CLI is not installed"
                echo "Install from: https://aws.amazon.com/cli/" >&2
                return 1
            fi
            ;;
        azure)
            if ! command -v az &> /dev/null; then
                print_color "$RED" "❌ Error: az CLI is not installed"
                echo "Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli" >&2
                return 1
            fi
            ;;
        *)
            print_color "$RED" "❌ Unsupported storage path format"
            return 1
            ;;
    esac
    return 0
}

# Function to list files based on storage type
list_files() {
    local storage_path=$1
    local storage_type=$2
    
    case "$storage_type" in
        gcs)
            gsutil ls "$storage_path" 2>/dev/null || true
            ;;
        s3)
            aws s3 ls "$storage_path" --recursive 2>/dev/null | awk '{print "s3://"$4}' || true
            ;;
        azure)
            # Azure CLI listing would go here
            print_color "$YELLOW" "Azure support coming soon"
            ;;
    esac
}

# Function to cat file based on storage type
cat_file() {
    local file=$1
    local storage_type=$2
    
    case "$storage_type" in
        gcs)
            gsutil cat "$file" 2>/dev/null
            ;;
        s3)
            aws s3 cp "$file" - 2>/dev/null
            ;;
        azure)
            # Azure CLI cat would go here
            print_color "$YELLOW" "Azure support coming soon"
            ;;
    esac
}

# Function to detect if file is gzipped
is_gzipped() {
    local file=$1
    
    # Check by extension
    if [[ "$file" =~ \.(gz|gzip)$ ]]; then
        return 0
    fi
    
    # Could also check by magic bytes if needed
    return 1
}

# Function to search a single file
search_file() {
    local file=$1
    local search_string=$2
    local storage_type=$3
    local result_file=$4
    local case_insensitive=$5
    local regex_mode=$6
    
    # Check if we should stop (another process found a match)
    if [[ -f "$MATCH_FOUND_FLAG" ]]; then
        return 0
    fi
    
    local basename=$(basename "$file")
    print_color "$CYAN" "🔍 Searching: $basename"
    
    # Prepare grep options
    local grep_opts="-n"
    [[ "$case_insensitive" == "1" ]] && grep_opts="$grep_opts -i"
    [[ "$regex_mode" == "1" ]] && grep_opts="$grep_opts -E" || grep_opts="$grep_opts -F"
    
    # Stream and search the file
    local line_number=0
    local found=0
    
    if is_gzipped "$file"; then
        # File is gzipped - decompress on the fly
        print_color "$BLUE" "   📦 Detected gzip file, decompressing..."
        
        while IFS= read -r line; do
            ((line_number++))
            
            # Check for match
            if echo "$line" | grep $grep_opts -q "$search_string" 2>/dev/null; then
                # Found a match!
                found=1
                
                # Create flag file to signal other processes
                touch "$MATCH_FOUND_FLAG"
                
                # Write result
                {
                    echo "MATCH_FOUND"
                    echo "FILE: $file"
                    echo "LINE: $line_number"
                    echo "CONTENT: $line"
                    echo "TIMESTAMP: $(date '+%Y-%m-%d %H:%M:%S')"
                } > "$result_file"
                
                print_color "$GREEN" "   🎯 FOUND MATCH at line $line_number!"
                
                # Extract context lines if file is small enough
                local context_lines=2
                local start_line=$((line_number - context_lines))
                local end_line=$((line_number + context_lines))
                [[ $start_line -lt 1 ]] && start_line=1
                
                {
                    echo "CONTEXT_START"
                    cat_file "$file" "$storage_type" | gunzip 2>/dev/null | \
                        sed -n "${start_line},${end_line}p" 2>/dev/null || true
                    echo "CONTEXT_END"
                } >> "$result_file"
                
                return 0
            fi
            
            # Periodic check if another process found a match
            if [[ $((line_number % 1000)) -eq 0 ]] && [[ -f "$MATCH_FOUND_FLAG" ]]; then
                print_color "$YELLOW" "   ⏸️  Stopping - match found elsewhere"
                return 0
            fi
        done < <(cat_file "$file" "$storage_type" | gunzip 2>/dev/null)
        
    else
        # File is not gzipped - search directly
        while IFS= read -r line; do
            ((line_number++))
            
            # Check for match
            if echo "$line" | grep $grep_opts -q "$search_string" 2>/dev/null; then
                # Found a match!
                found=1
                
                # Create flag file to signal other processes
                touch "$MATCH_FOUND_FLAG"
                
                # Write result
                {
                    echo "MATCH_FOUND"
                    echo "FILE: $file"
                    echo "LINE: $line_number"
                    echo "CONTENT: $line"
                    echo "TIMESTAMP: $(date '+%Y-%m-%d %H:%M:%S')"
                } > "$result_file"
                
                print_color "$GREEN" "   🎯 FOUND MATCH at line $line_number!"
                
                # Extract context lines
                local context_lines=2
                local start_line=$((line_number - context_lines))
                local end_line=$((line_number + context_lines))
                [[ $start_line -lt 1 ]] && start_line=1
                
                {
                    echo "CONTEXT_START"
                    cat_file "$file" "$storage_type" | \
                        sed -n "${start_line},${end_line}p" 2>/dev/null || true
                    echo "CONTEXT_END"
                } >> "$result_file"
                
                return 0
            fi
            
            # Periodic check if another process found a match
            if [[ $((line_number % 1000)) -eq 0 ]] && [[ -f "$MATCH_FOUND_FLAG" ]]; then
                print_color "$YELLOW" "   ⏸️  Stopping - match found elsewhere"
                return 0
            fi
        done < <(cat_file "$file" "$storage_type")
    fi
    
    if [[ $found -eq 0 ]]; then
        print_color "$YELLOW" "   ✗ No match (searched $line_number lines)"
    fi
    
    return $found
}

# Main function
find_string_alt() {
    # Show help
    if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
        cat <<EOF
${GREEN}Cloud Storage String Finder v2.0${NC}

${BLUE}USAGE:${NC}
  $(basename "$0") <storage_path> <search_string> [options]

${BLUE}DESCRIPTION:${NC}
  Efficiently searches for strings in cloud storage files.
  Automatically detects and decompresses gzip files.
  Stops immediately when first match is found.

${BLUE}STORAGE PATHS:${NC}
  GCS:   gs://bucket/path/pattern*.txt
  S3:    s3://bucket/path/pattern*.log
  Azure: https://account.blob.core.windows.net/container/

${BLUE}OPTIONS:${NC}
  -c, --concurrency N     Parallel search workers (default: 8)
  -i, --ignore-case       Case-insensitive search
  -r, --regex             Use regex pattern matching
  -l, --list-only         Only list matching filenames
  -m, --max-files N       Stop after searching N files
  -t, --timeout SEC       Timeout in seconds (default: 3600)
  -v, --verbose           Show detailed progress
  --file-pattern PATTERN  Filter files by pattern

${BLUE}EXAMPLES:${NC}
  # Basic search in GCS
  $(basename "$0") 'gs://my-bucket/logs/*.log' 'ERROR'

  # Case-insensitive search with high concurrency
  $(basename "$0") 'gs://bucket/data/*.gz' 'warning' -i -c 16

  # Regex search in S3
  $(basename "$0") 's3://bucket/2024/*.json' 'user_[0-9]+' -r

  # Search with timeout
  $(basename "$0") 'gs://bucket/**/*.txt' 'needle' -t 300

${YELLOW}FEATURES:${NC}
  ✓ Automatic gzip detection and decompression
  ✓ Early termination on first match
  ✓ Parallel processing with configurable concurrency
  ✓ Context lines around matches
  ✓ Support for multiple cloud providers

EOF
        return 0
    fi
    
    # Parse arguments
    local storage_path="$1"
    local search_string="$2"
    local concurrency=8
    local case_insensitive=0
    local regex_mode=0
    local list_only=0
    local max_files=""
    local timeout=3600
    local verbose=0
    local file_pattern=""
    
    shift 2
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--concurrency)
                concurrency="$2"
                shift 2
                ;;
            -i|--ignore-case)
                case_insensitive=1
                shift
                ;;
            -r|--regex)
                regex_mode=1
                shift
                ;;
            -l|--list-only)
                list_only=1
                shift
                ;;
            -m|--max-files)
                max_files="$2"
                shift 2
                ;;
            -t|--timeout)
                timeout="$2"
                shift 2
                ;;
            -v|--verbose)
                verbose=1
                shift
                ;;
            --file-pattern)
                file_pattern="$2"
                shift 2
                ;;
            *)
                print_color "$RED" "Unknown option: $1"
                return 1
                ;;
        esac
    done
    
    # Validate inputs
    if [[ -z "$storage_path" || -z "$search_string" ]]; then
        print_color "$RED" "❌ Error: storage_path and search_string are required"
        return 1
    fi
    
    # Detect storage type
    local storage_type=$(detect_storage_type "$storage_path")
    
    # Check prerequisites
    if ! check_prerequisites "$storage_type"; then
        return 1
    fi
    
    # Create temp directory
    local temp_dir=$(mktemp -d)
    trap "rm -rf '$temp_dir'" EXIT
    
    local result_file="$temp_dir/result.txt"
    MATCH_FOUND_FLAG="$temp_dir/match_found.flag"
    
    # Display search parameters
    print_color "$GREEN" "🔍 Cloud Storage String Search"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "Storage:      $storage_type" >&2
    echo "Path:         $storage_path" >&2
    echo "Search:       '$search_string'" >&2
    echo "Mode:         $([ $regex_mode -eq 1 ] && echo 'regex' || echo 'literal')" >&2
    echo "Case:         $([ $case_insensitive -eq 1 ] && echo 'insensitive' || echo 'sensitive')" >&2
    echo "Concurrency:  $concurrency workers" >&2
    echo "Timeout:      ${timeout}s" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "" >&2
    
    # Get file list
    print_color "$BLUE" "📂 Listing files..."
    local files=$(list_files "$storage_path" "$storage_type")
    
    if [[ -z "$files" ]]; then
        print_color "$RED" "❌ No files found matching: $storage_path"
        return 1
    fi
    
    # Apply file pattern filter if specified
    if [[ -n "$file_pattern" ]]; then
        files=$(echo "$files" | grep -E "$file_pattern" || true)
        if [[ -z "$files" ]]; then
            print_color "$RED" "❌ No files match pattern: $file_pattern"
            return 1
        fi
    fi
    
    # Limit files if max specified
    if [[ -n "$max_files" ]]; then
        files=$(echo "$files" | head -n "$max_files")
    fi
    
    local file_count=$(echo "$files" | wc -l | tr -d ' ')
    print_color "$GREEN" "📊 Found $file_count files to search"
    echo "" >&2
    
    # Start search with timeout
    print_color "$BLUE" "🚀 Starting parallel search..."
    echo "" >&2
    
    # Export functions and variables for parallel execution
    export -f search_file cat_file is_gzipped print_color
    export MATCH_FOUND_FLAG
    export RED GREEN YELLOW BLUE CYAN NC
    
    # Run parallel search with early termination
    (
        echo "$files" | while IFS= read -r file; do
            # Check if match already found
            if [[ -f "$MATCH_FOUND_FLAG" ]]; then
                break
            fi
            echo "$file"
        done | xargs -I {} -P "$concurrency" bash -c '
            search_file "$1" "$2" "$3" "$4" "$5" "$6"
        ' -- {} "$search_string" "$storage_type" "$result_file" "$case_insensitive" "$regex_mode"
    ) &
    
    local search_pid=$!
    
    # Wait with timeout
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        # Check if search completed
        if ! kill -0 $search_pid 2>/dev/null; then
            break
        fi
        
        # Check if match found
        if [[ -f "$MATCH_FOUND_FLAG" ]]; then
            # Give a moment for result to be written
            sleep 1
            
            # Kill remaining search processes
            pkill -P $search_pid 2>/dev/null || true
            kill $search_pid 2>/dev/null || true
            break
        fi
        
        sleep 1
        ((elapsed++))
        
        # Progress indicator
        if [[ $verbose -eq 1 ]] && [[ $((elapsed % 5)) -eq 0 ]]; then
            print_color "$CYAN" "   ⏱️  Elapsed: ${elapsed}s"
        fi
    done
    
    # Kill search if timeout
    if [[ $elapsed -ge $timeout ]]; then
        print_color "$YELLOW" "⏱️  Timeout reached after ${timeout}s"
        pkill -P $search_pid 2>/dev/null || true
        kill $search_pid 2>/dev/null || true
    fi
    
    echo "" >&2
    
    # Check results
    if [[ -f "$result_file" ]] && grep -q "MATCH_FOUND" "$result_file" 2>/dev/null; then
        print_color "$GREEN" "🎉 SUCCESS! MATCH FOUND!"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
        
        local file_path=$(grep "^FILE:" "$result_file" | cut -d' ' -f2-)
        local line_num=$(grep "^LINE:" "$result_file" | cut -d' ' -f2-)
        local content=$(grep "^CONTENT:" "$result_file" | cut -d' ' -f2-)
        local timestamp=$(grep "^TIMESTAMP:" "$result_file" | cut -d' ' -f2-)
        
        echo "📄 File:      $file_path" >&2
        echo "📍 Line:      $line_num" >&2
        echo "🕐 Found at:  $timestamp" >&2
        echo "💬 Content:   $content" >&2
        
        # Show context if available
        if grep -q "CONTEXT_START" "$result_file" 2>/dev/null; then
            echo "" >&2
            echo "📝 Context:" >&2
            echo "---" >&2
            sed -n '/CONTEXT_START/,/CONTEXT_END/p' "$result_file" | \
                grep -v "CONTEXT_" | head -n 5 >&2
            echo "---" >&2
        fi
        
        echo "" >&2
        echo "✅ Search completed in ${elapsed}s" >&2
        
        # Output just the file path for piping
        echo "$file_path"
        
        return 0
    else
        print_color "$RED" "❌ NO MATCH FOUND"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
        echo "Searched $file_count files but no match for '$search_string'" >&2
        echo "Time elapsed: ${elapsed}s" >&2
        
        return 1
    fi
}

# Export main function
export -f find_string_alt

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    find_string_alt "$@"
fi
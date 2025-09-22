#!/bin/bash

# Extract and count unique basenames from bucket files
get_basenames() {
    # Show help if no arguments or help requested
    if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: get_basenames <bucket-path> [--count] [--sort-by-count] [--pattern=PATTERN]"
        echo ""
        echo "Extract and analyze unique basenames from cloud storage files."
        echo ""
        echo "Arguments:"
        echo "  bucket-path      GCS bucket path (e.g., gs://bucket/path/)"
        echo ""
        echo "Options:"
        echo "  --count          Show occurrence count for each basename"
        echo "  --sort-by-count  Sort results by count (descending)"
        echo "  --pattern=REGEX  Filter basenames with regex pattern"
        echo "  --extensions     Show file extensions summary"
        echo ""
        echo "Examples:"
        echo "  get_basenames gs://my-bucket/data/"
        echo "  get_basenames gs://bucket/ --count --sort-by-count"
        echo "  get_basenames gs://logs/ --pattern='2024.*' --count"
        echo "  get_basenames gs://files/ --extensions"
        return 0
    fi

    local bucket_path="$1"
    local show_count=false
    local sort_by_count=false
    local pattern=""
    local show_extensions=false

    # Parse arguments
    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --count)
                show_count=true
                shift
                ;;
            --sort-by-count)
                sort_by_count=true
                show_count=true  # Implied when sorting by count
                shift
                ;;
            --pattern=*)
                pattern="${1#*=}"
                shift
                ;;
            --extensions)
                show_extensions=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                return 1
                ;;
        esac
    done

    # Validate input
    if [[ ! "$bucket_path" =~ ^gs:// ]]; then
        echo "❌ Error: Path must start with gs://"
        return 1
    fi

    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        echo "❌ Error: gsutil is not installed or not in PATH"
        return 1
    fi

    echo "🔍 Analyzing basenames in: $bucket_path"
    if [[ -n "$pattern" ]]; then
        echo "📝 Pattern filter: $pattern"
    fi
    echo ""

    # Create temporary directory
    local temp_dir=$(mktemp -d)
    local files_list="$temp_dir/files.txt"
    local basenames_list="$temp_dir/basenames.txt"

    echo "📂 Listing files..."

    # Get all files (not directories)
    if ! gsutil -m ls "${bucket_path}**" 2>/dev/null | grep -v '/$' > "$files_list"; then
        echo "❌ Error: Could not list files in $bucket_path"
        rm -rf "$temp_dir"
        return 1
    fi

    local total_files=$(wc -l < "$files_list")
    echo "📊 Found $(printf "%'d" $total_files) files"
    echo ""

    # Extract basenames
    echo "🔧 Extracting basenames..."

    while IFS= read -r file; do
        basename "$file"
    done < "$files_list" > "$basenames_list"

    # Apply pattern filter if specified
    if [[ -n "$pattern" ]]; then
        local filtered_list="$temp_dir/filtered.txt"
        grep -E "$pattern" "$basenames_list" > "$filtered_list" || true
        mv "$filtered_list" "$basenames_list"

        local filtered_count=$(wc -l < "$basenames_list")
        echo "🔍 Filtered to $(printf "%'d" $filtered_count) files matching pattern"
        echo ""
    fi

    # Show extensions summary if requested
    if $show_extensions; then
        echo "📋 File Extensions Summary:"
        echo "=========================="

        # Extract extensions and count them
        sed 's/.*\.//' "$basenames_list" | sort | uniq -c | sort -nr | while read -r count ext; do
            printf "%8s files with .%s extension\n" "$(printf "%'d" $count)" "$ext"
        done

        echo ""
    fi

    # Process basenames
    echo "📋 Basename Analysis:"
    echo "===================="

    if $show_count; then
        if $sort_by_count; then
            # Sort by count descending
            sort "$basenames_list" | uniq -c | sort -nr | while read -r count basename; do
                printf "%8s  %s\n" "$(printf "%'d" $count)" "$basename"
            done
        else
            # Show count but don't sort by it (alphabetical order)
            sort "$basenames_list" | uniq -c | while read -r count basename; do
                printf "%8s  %s\n" "$(printf "%'d" $count)" "$basename"
            done
        fi
    else
        # Just unique basenames, no count
        sort "$basenames_list" | uniq
    fi

    echo ""

    # Summary statistics
    echo "📊 Summary:"
    echo "==========="

    local unique_basenames=$(sort "$basenames_list" | uniq | wc -l)
    local total_basenames=$(wc -l < "$basenames_list")

    echo "Total files processed: $(printf "%'d" $total_basenames)"
    echo "Unique basenames: $(printf "%'d" $unique_basenames)"

    if [[ $unique_basenames -gt 0 && $total_basenames -gt 0 ]]; then
        local avg_files_per_basename=$((total_basenames / unique_basenames))
        echo "Average files per basename: $avg_files_per_basename"
    fi

    # Show most common if we have counts
    if $show_count && [[ $unique_basenames -gt 1 ]]; then
        echo ""
        echo "🏆 Most Common Basenames:"
        sort "$basenames_list" | uniq -c | sort -nr | head -5 | while read -r count basename; do
            printf "   %s (%s files)\n" "$basename" "$(printf "%'d" $count)"
        done
    fi

    echo ""

    # Cleanup
    rm -rf "$temp_dir"

    return 0
}

# Export function
export -f get_basenames

# Run directly if executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    get_basenames "$@"
fi
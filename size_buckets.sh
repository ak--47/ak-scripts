#!/bin/bash

# Calculate total size across all GCS buckets
size_buckets() {
    # Show help if no arguments or help requested
    if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: size_buckets [--sort-by-size]"
        echo ""
        echo "Calculate and display sizes of all GCS buckets with grand total."
        echo ""
        echo "Options:"
        echo "  --sort-by-size    Sort buckets by size (largest first)"
        echo ""
        echo "Example:"
        echo "  size_buckets"
        echo "  size_buckets --sort-by-size"
        return 0
    fi

    local sort_by_size=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --sort-by-size)
                sort_by_size=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                return 1
                ;;
        esac
    done

    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        echo "Error: gsutil is not installed or not in PATH"
        return 1
    fi

    local total_bytes=0
    local temp_file=$(mktemp)

    echo ""
    echo "Calculating bucket sizes..."
    echo ""

    # Get all buckets and calculate sizes
    while IFS= read -r bucket; do
        echo "Processing: $bucket"

        # Get raw byte count
        local bytes=$(gsutil du -s "$bucket" 2>/dev/null | awk '{print $1}')
        if [[ -z "$bytes" ]]; then
            bytes=0
        fi

        # Convert to human-readable
        local hr=$(numfmt --to=iec --suffix=B --format="%.2f" "$bytes" 2>/dev/null || echo "0B")

        # Store for sorting if needed
        echo -e "$bytes\t$bucket\t$hr" >> "$temp_file"

        # Accumulate total
        total_bytes=$((total_bytes + bytes))
    done < <(gsutil ls 2>/dev/null)

    echo ""
    echo "Bucket sizes:"
    echo "-------------"

    # Sort and display results
    if $sort_by_size; then
        # Sort by bytes (first column) in descending order
        sort -nr "$temp_file" | while IFS=$'\t' read -r bytes bucket hr; do
            printf "%-45s %10s\n" "$bucket" "$hr"
        done
    else
        # Display in original order
        while IFS=$'\t' read -r bytes bucket hr; do
            printf "%-45s %10s\n" "$bucket" "$hr"
        done < "$temp_file"
    fi

    echo ""
    echo "Grand total:"
    echo "-------------"

    # Human-readable grand total
    local grand_hr=$(numfmt --to=iec --suffix=B --format="%.2f" "$total_bytes" 2>/dev/null || echo "0B")
    printf "%s across all buckets\n\n" "$grand_hr"

    # Cleanup
    rm -f "$temp_file"

    return 0
}

# Export function
export -f size_buckets

# Run directly if executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    size_buckets "$@"
fi
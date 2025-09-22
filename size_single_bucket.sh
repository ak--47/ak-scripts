#!/bin/bash

# Calculate sizes for items in a specific GCS bucket or path
size_single_bucket() {
    # Show help if no arguments or help requested
    if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: size_single_bucket <gcs-path> [--sort-by-size]"
        echo ""
        echo "Calculate sizes for all items in a specific GCS bucket or path."
        echo ""
        echo "Arguments:"
        echo "  gcs-path         GCS bucket or path (e.g., gs://bucket or gs://bucket/folder/)"
        echo ""
        echo "Options:"
        echo "  --sort-by-size   Sort items by size (largest first)"
        echo ""
        echo "Examples:"
        echo "  size_single_bucket gs://my-bucket/"
        echo "  size_single_bucket gs://my-bucket/data/ --sort-by-size"
        return 0
    fi

    local bucket_path="$1"
    local sort_by_size=false

    # Parse remaining arguments
    shift
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

    # Validate input
    if [[ ! "$bucket_path" =~ ^gs:// ]]; then
        echo "Error: Path must start with gs://"
        return 1
    fi

    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        echo "Error: gsutil is not installed or not in PATH"
        return 1
    fi

    # Ensure trailing slash for directories
    [[ "$bucket_path" != */ ]] && bucket_path="${bucket_path}/"

    echo ""
    echo "Calculating sizes for items in ${bucket_path}"
    echo ""

    # Get all top-level items
    local items
    items=$(gsutil ls "$bucket_path" 2>/dev/null)

    if [[ -z "$items" ]]; then
        echo "No items found in ${bucket_path} or path is not accessible."
        return 1
    fi

    local temp_file=$(mktemp)

    # Process each item
    while IFS= read -r item; do
        echo "Processing: $(basename "$item")"

        # Determine if it's a directory or file
        local pattern
        if [[ "$item" == */ ]]; then
            pattern="${item}**"  # Include all files in subdirectories
        else
            pattern="$item"
        fi

        # Get size with error handling
        local size_output
        size_output=$(gsutil du -sh "$pattern" 2>/dev/null)

        if [[ -z "$size_output" ]]; then
            echo -e "0\t$item\tN/A" >> "$temp_file"
        else
            # Parse size output (number and unit)
            local size_value size_unit
            size_value=$(echo "$size_output" | awk '{print $1}')
            size_unit=$(echo "$size_output" | awk '{print $2}')
            local size_display="${size_value} ${size_unit}"

            # Convert to bytes for sorting
            local bytes=0
            case "$size_unit" in
                "B") bytes="$size_value" ;;
                "KiB") bytes=$(echo "$size_value * 1024" | bc 2>/dev/null || echo "0") ;;
                "MiB") bytes=$(echo "$size_value * 1024 * 1024" | bc 2>/dev/null || echo "0") ;;
                "GiB") bytes=$(echo "$size_value * 1024 * 1024 * 1024" | bc 2>/dev/null || echo "0") ;;
                "TiB") bytes=$(echo "$size_value * 1024 * 1024 * 1024 * 1024" | bc 2>/dev/null || echo "0") ;;
                *) bytes="0" ;;
            esac

            echo -e "${bytes}\t${item}\t${size_display}" >> "$temp_file"
        fi
    done <<< "$items"

    echo ""
    echo "Results:"
    echo "--------"

    # Display results
    if $sort_by_size; then
        # Sort by bytes (descending)
        sort -nr "$temp_file" | while IFS=$'\t' read -r bytes item size_display; do
            printf "%-60s %15s\n" "$item" "$size_display"
        done
    else
        # Display in original order
        while IFS=$'\t' read -r bytes item size_display; do
            printf "%-60s %15s\n" "$item" "$size_display"
        done < "$temp_file"
    fi

    echo ""

    # Calculate total if there are multiple items
    local item_count=$(wc -l < "$temp_file")
    if [[ $item_count -gt 1 ]]; then
        echo "Summary:"
        echo "--------"
        echo "Total items: $item_count"

        # Calculate grand total
        local total_bytes=0
        while IFS=$'\t' read -r bytes item size_display; do
            total_bytes=$((total_bytes + bytes))
        done < "$temp_file"

        local total_hr=$(numfmt --to=iec --suffix=B --format="%.2f" "$total_bytes" 2>/dev/null || echo "${total_bytes}B")
        echo "Total size: $total_hr"
        echo ""
    fi

    # Cleanup
    rm -f "$temp_file"

    return 0
}

# Export function
export -f size_single_bucket

# Run directly if executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    size_single_bucket "$@"
fi
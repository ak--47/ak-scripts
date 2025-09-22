#!/bin/bash

# Advanced bucket synchronization with filtering and reporting
sync_buckets() {
    # Show help if no arguments or help requested
    if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: sync_buckets <source> <destination> [options]"
        echo ""
        echo "Advanced bucket synchronization with filtering and detailed reporting."
        echo ""
        echo "Arguments:"
        echo "  source       Source bucket/path (gs://source-bucket/path/)"
        echo "  destination  Destination bucket/path (gs://dest-bucket/path/)"
        echo ""
        echo "Options:"
        echo "  --dry-run              Show what would be synchronized without doing it"
        echo "  --delete               Delete files in destination not in source"
        echo "  --exclude=PATTERN      Exclude files matching pattern (can be used multiple times)"
        echo "  --include=PATTERN      Only include files matching pattern"
        echo "  --newer-than=DAYS      Only sync files newer than N days"
        echo "  --size-threshold=SIZE  Only sync files larger than SIZE (e.g., 10M, 1G)"
        echo "  --report               Generate detailed sync report"
        echo ""
        echo "Examples:"
        echo "  sync_buckets gs://source/ gs://dest/ --dry-run"
        echo "  sync_buckets gs://logs/ gs://backup/ --delete --exclude='*.tmp'"
        echo "  sync_buckets gs://data/ gs://archive/ --newer-than=30 --report"
        echo "  sync_buckets gs://files/ gs://mirror/ --size-threshold=100M"
        return 0
    fi

    local source="$1"
    local destination="$2"
    local dry_run=false
    local delete_extra=false
    local excludes=()
    local include_pattern=""
    local newer_than=""
    local size_threshold=""
    local generate_report=false

    # Parse arguments
    shift 2
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                dry_run=true
                shift
                ;;
            --delete)
                delete_extra=true
                shift
                ;;
            --exclude=*)
                excludes+=("${1#*=}")
                shift
                ;;
            --include=*)
                include_pattern="${1#*=}"
                shift
                ;;
            --newer-than=*)
                newer_than="${1#*=}"
                shift
                ;;
            --size-threshold=*)
                size_threshold="${1#*=}"
                shift
                ;;
            --report)
                generate_report=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                return 1
                ;;
        esac
    done

    # Validate input
    if [[ ! "$source" =~ ^gs:// ]] || [[ ! "$destination" =~ ^gs:// ]]; then
        echo "❌ Error: Both source and destination must start with gs://"
        return 1
    fi

    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        echo "❌ Error: gsutil is not installed or not in PATH"
        return 1
    fi

    echo "🔄 Advanced Bucket Synchronization"
    echo "================================="
    echo "Source: $source"
    echo "Destination: $destination"
    if $dry_run; then
        echo "🔍 DRY RUN MODE - No changes will be made"
    fi
    if $delete_extra; then
        echo "🗑️  Delete mode: Extra files in destination will be removed"
    fi
    if [[ ${#excludes[@]} -gt 0 ]]; then
        echo "🚫 Exclude patterns: ${excludes[*]}"
    fi
    if [[ -n "$include_pattern" ]]; then
        echo "✅ Include pattern: $include_pattern"
    fi
    if [[ -n "$newer_than" ]]; then
        echo "📅 Only files newer than: $newer_than days"
    fi
    if [[ -n "$size_threshold" ]]; then
        echo "📏 Size threshold: $size_threshold"
    fi
    echo ""

    # Create temporary directory for processing
    local temp_dir=$(mktemp -d)
    local source_list="$temp_dir/source.txt"
    local dest_list="$temp_dir/dest.txt"
    local sync_plan="$temp_dir/sync_plan.txt"
    local report_file="$temp_dir/report.txt"

    echo "📂 Analyzing source and destination..."

    # Get source files with metadata
    gsutil ls -l "$source**" 2>/dev/null | grep -v 'TOTAL:' | awk 'NF>1 {print $3 "\t" $1 "\t" $2}' > "$source_list"
    local source_count=$(wc -l < "$source_list")

    # Get destination files with metadata
    gsutil ls -l "$destination**" 2>/dev/null | grep -v 'TOTAL:' | awk 'NF>1 {print $3 "\t" $1 "\t" $2}' > "$dest_list"
    local dest_count=$(wc -l < "$dest_list")

    echo "📊 Source files: $(printf "%'d" $source_count)"
    echo "📊 Destination files: $(printf "%'d" $dest_count)"
    echo ""

    # Apply filters to source list
    local filtered_source="$temp_dir/filtered_source.txt"
    cp "$source_list" "$filtered_source"

    # Apply include pattern
    if [[ -n "$include_pattern" ]]; then
        grep "$include_pattern" "$filtered_source" > "$temp_dir/temp.txt" || true
        mv "$temp_dir/temp.txt" "$filtered_source"
    fi

    # Apply exclude patterns
    for exclude in "${excludes[@]}"; do
        grep -v "$exclude" "$filtered_source" > "$temp_dir/temp.txt" || true
        mv "$temp_dir/temp.txt" "$filtered_source"
    done

    # Apply date filter
    if [[ -n "$newer_than" ]]; then
        local cutoff_date=$(date -d "${newer_than} days ago" '+%Y-%m-%d' 2>/dev/null || date -v-"${newer_than}"d '+%Y-%m-%d' 2>/dev/null)
        if [[ -n "$cutoff_date" ]]; then
            awk -F'\t' -v cutoff="$cutoff_date" '$2 > cutoff' "$filtered_source" > "$temp_dir/temp.txt"
            mv "$temp_dir/temp.txt" "$filtered_source"
        fi
    fi

    # Apply size filter
    if [[ -n "$size_threshold" ]]; then
        # Convert size threshold to bytes
        local threshold_bytes
        case "$size_threshold" in
            *K|*k) threshold_bytes=$(echo "${size_threshold%?} * 1024" | bc) ;;
            *M|*m) threshold_bytes=$(echo "${size_threshold%?} * 1024 * 1024" | bc) ;;
            *G|*g) threshold_bytes=$(echo "${size_threshold%?} * 1024 * 1024 * 1024" | bc) ;;
            *) threshold_bytes="$size_threshold" ;;
        esac

        awk -F'\t' -v threshold="$threshold_bytes" '$1 >= threshold' "$filtered_source" > "$temp_dir/temp.txt"
        mv "$temp_dir/temp.txt" "$filtered_source"
    fi

    local filtered_count=$(wc -l < "$filtered_source")
    echo "📊 Files after filtering: $(printf "%'d" $filtered_count)"

    # Create sync plan
    echo "🎯 Creating synchronization plan..."

    {
        echo "=== SYNC PLAN ==="
        echo "Files to copy/update:"

        # Find files that need to be copied or updated
        while IFS=$'\t' read -r size date file; do
            local dest_file="${file/$source/$destination}"
            local dest_entry=$(grep -F "$dest_file" "$dest_list" || echo "")

            if [[ -z "$dest_entry" ]]; then
                echo "COPY\t$file\t$dest_file\tNew file"
            else
                local dest_date=$(echo "$dest_entry" | cut -f2)
                if [[ "$date" > "$dest_date" ]]; then
                    echo "UPDATE\t$file\t$dest_file\tNewer version"
                fi
            fi
        done < "$filtered_source"

        if $delete_extra; then
            echo ""
            echo "Files to delete:"

            # Find files in destination that don't exist in filtered source
            while IFS=$'\t' read -r size date file; do
                local source_file="${file/$destination/$source}"
                if ! grep -qF "$source_file" "$filtered_source"; then
                    echo "DELETE\t$file\t\tExtra file"
                fi
            done < "$dest_list"
        fi
    } > "$sync_plan"

    # Show sync plan summary
    local copy_count=$(grep "^COPY" "$sync_plan" | wc -l)
    local update_count=$(grep "^UPDATE" "$sync_plan" | wc -l)
    local delete_count=$(grep "^DELETE" "$sync_plan" | wc -l)

    echo ""
    echo "📋 Synchronization Plan:"
    echo "======================="
    echo "Files to copy: $(printf "%'d" $copy_count)"
    echo "Files to update: $(printf "%'d" $update_count)"
    if $delete_extra; then
        echo "Files to delete: $(printf "%'d" $delete_count)"
    fi

    if [[ $copy_count -eq 0 && $update_count -eq 0 && $delete_count -eq 0 ]]; then
        echo "✅ No changes needed - buckets are already synchronized!"
        rm -rf "$temp_dir"
        return 0
    fi

    if $dry_run; then
        echo ""
        echo "🔍 DRY RUN - Changes that would be made:"
        cat "$sync_plan"
        echo ""
        echo "ℹ️  Use without --dry-run to perform actual synchronization"
        rm -rf "$temp_dir"
        return 0
    fi

    echo ""
    read -p "Proceed with synchronization? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Synchronization cancelled"
        rm -rf "$temp_dir"
        return 1
    fi

    echo ""
    echo "🚀 Starting synchronization..."
    local start_time=$(date +%s)

    # Perform the actual sync
    local success_count=0
    local error_count=0

    # Process copy and update operations
    grep "^COPY\|^UPDATE" "$sync_plan" | while IFS=$'\t' read -r action source_file dest_file reason; do
        echo "[$action] $(basename "$source_file")"
        if gsutil cp "$source_file" "$dest_file" 2>/dev/null; then
            ((success_count++))
            echo "✅ $action: $(basename "$source_file")"
        else
            ((error_count++))
            echo "❌ Failed: $(basename "$source_file")"
        fi
    done

    # Process delete operations
    if $delete_extra; then
        grep "^DELETE" "$sync_plan" | while IFS=$'\t' read -r action file _ reason; do
            echo "[DELETE] $(basename "$file")"
            if gsutil rm "$file" 2>/dev/null; then
                echo "✅ Deleted: $(basename "$file")"
            else
                echo "❌ Failed to delete: $(basename "$file")"
            fi
        done
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    echo ""
    echo "🎉 Synchronization Complete!"
    echo "============================"
    echo "Duration: ${duration}s"

    # Generate detailed report if requested
    if $generate_report; then
        {
            echo "BUCKET SYNCHRONIZATION REPORT"
            echo "Generated: $(date)"
            echo "Source: $source"
            echo "Destination: $destination"
            echo ""
            echo "SUMMARY:"
            echo "Files copied: $copy_count"
            echo "Files updated: $update_count"
            if $delete_extra; then
                echo "Files deleted: $delete_count"
            fi
            echo "Duration: ${duration}s"
            echo ""
            echo "DETAILED PLAN:"
            cat "$sync_plan"
        } > "$report_file"

        echo "📊 Detailed report saved to: $report_file"
    fi

    # Cleanup
    rm -rf "$temp_dir"

    return 0
}

# Export function
export -f sync_buckets

# Run directly if executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    sync_buckets "$@"
fi
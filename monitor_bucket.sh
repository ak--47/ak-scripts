#!/bin/bash

# Monitor bucket changes and file activity in real-time
monitor_bucket() {
    # Show help if no arguments or help requested
    if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: monitor_bucket <bucket-path> [options]"
        echo ""
        echo "Monitor bucket changes and file activity in real-time."
        echo ""
        echo "Arguments:"
        echo "  bucket-path      GCS bucket path to monitor (gs://bucket/path/)"
        echo ""
        echo "Options:"
        echo "  --interval=SECONDS   Check interval in seconds (default: 30)"
        echo "  --log-file=PATH      Log changes to file"
        echo "  --filter=PATTERN     Only monitor files matching pattern"
        echo "  --webhook=URL        Send notifications to webhook URL"
        echo "  --size-changes       Monitor file size changes"
        echo "  --summary-only       Only show summary statistics"
        echo ""
        echo "Examples:"
        echo "  monitor_bucket gs://data-bucket/uploads/"
        echo "  monitor_bucket gs://logs/ --interval=10 --filter='*.json'"
        echo "  monitor_bucket gs://files/ --log-file=/tmp/bucket.log"
        echo "  monitor_bucket gs://events/ --webhook=https://hooks.slack.com/..."
        return 0
    fi

    local bucket_path="$1"
    local interval=30
    local log_file=""
    local filter_pattern=""
    local webhook_url=""
    local monitor_sizes=false
    local summary_only=false

    # Parse arguments
    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --interval=*)
                interval="${1#*=}"
                shift
                ;;
            --log-file=*)
                log_file="${1#*=}"
                shift
                ;;
            --filter=*)
                filter_pattern="${1#*=}"
                shift
                ;;
            --webhook=*)
                webhook_url="${1#*=}"
                shift
                ;;
            --size-changes)
                monitor_sizes=true
                shift
                ;;
            --summary-only)
                summary_only=true
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
        echo "❌ Error: Bucket path must start with gs://"
        return 1
    fi

    # Check required tools
    if ! command -v gsutil &> /dev/null; then
        echo "❌ Error: gsutil is not installed or not in PATH"
        return 1
    fi

    echo "👁️  Bucket Monitor Starting"
    echo "==========================="
    echo "Bucket: $bucket_path"
    echo "Check interval: ${interval}s"
    if [[ -n "$filter_pattern" ]]; then
        echo "Filter: $filter_pattern"
    fi
    if [[ -n "$log_file" ]]; then
        echo "Log file: $log_file"
    fi
    if [[ -n "$webhook_url" ]]; then
        echo "Webhook: $webhook_url"
    fi
    echo ""
    echo "🚀 Starting monitoring... (Press Ctrl+C to stop)"
    echo ""

    # Create temporary directory
    local temp_dir=$(mktemp -d)
    local current_state="$temp_dir/current.txt"
    local previous_state="$temp_dir/previous.txt"
    local changes_file="$temp_dir/changes.txt"

    # Initialize log file if specified
    if [[ -n "$log_file" ]]; then
        echo "# Bucket Monitor Log - Started $(date)" > "$log_file"
        echo "# Monitoring: $bucket_path" >> "$log_file"
        echo "# Interval: ${interval}s" >> "$log_file"
        echo "#" >> "$log_file"
    fi

    # Function to send webhook notification
    send_webhook() {
        local message="$1"
        if [[ -n "$webhook_url" ]] && command -v curl &> /dev/null; then
            curl -X POST "$webhook_url" \
                -H "Content-Type: application/json" \
                -d "{\"text\":\"$message\"}" \
                >/dev/null 2>&1
        fi
    }

    # Function to get bucket state
    get_bucket_state() {
        local output_file="$1"
        local pattern="${bucket_path}**"

        if [[ -n "$filter_pattern" ]]; then
            gsutil ls -l "$pattern" 2>/dev/null | grep -v 'TOTAL:' | grep "$filter_pattern" | awk 'NF>1 {print $3 "\t" $1 "\t" $2}' > "$output_file"
        else
            gsutil ls -l "$pattern" 2>/dev/null | grep -v 'TOTAL:' | awk 'NF>1 {print $3 "\t" $1 "\t" $2}' > "$output_file"
        fi
    }

    # Function to analyze changes
    analyze_changes() {
        local prev="$1"
        local curr="$2"
        local changes="$3"

        > "$changes"  # Clear changes file

        # Find new files
        comm -13 <(cut -f1 "$prev" | sort) <(cut -f1 "$curr" | sort) | while read -r file; do
            local file_info=$(grep -F "$file" "$curr")
            local size=$(echo "$file_info" | cut -f2)
            echo -e "NEW\t$file\t$size" >> "$changes"
        done

        # Find deleted files
        comm -23 <(cut -f1 "$prev" | sort) <(cut -f1 "$curr" | sort) | while read -r file; do
            echo -e "DELETED\t$file\t" >> "$changes"
        done

        # Find modified files (if monitoring sizes)
        if $monitor_sizes; then
            comm -12 <(cut -f1 "$prev" | sort) <(cut -f1 "$curr" | sort) | while read -r file; do
                local prev_size=$(grep -F "$file" "$prev" | cut -f2)
                local curr_size=$(grep -F "$file" "$curr" | cut -f2)

                if [[ "$prev_size" != "$curr_size" ]]; then
                    echo -e "MODIFIED\t$file\t$prev_size -> $curr_size" >> "$changes"
                fi
            done
        fi
    }

    # Function to format file size
    format_size() {
        local bytes="$1"
        if command -v numfmt &> /dev/null; then
            numfmt --to=iec --suffix=B --format="%.1f" "$bytes" 2>/dev/null || echo "${bytes}B"
        else
            echo "${bytes}B"
        fi
    }

    # Initial state capture
    echo "📊 Capturing initial state..."
    get_bucket_state "$current_state"
    local file_count=$(wc -l < "$current_state")
    echo "📂 Initial file count: $(printf "%'d" $file_count)"
    echo ""

    # Monitoring loop
    local iteration=0
    while true; do
        sleep "$interval"
        ((iteration++))

        # Save previous state and get current state
        cp "$current_state" "$previous_state"
        get_bucket_state "$current_state"

        # Analyze changes
        analyze_changes "$previous_state" "$current_state" "$changes_file"

        local new_count=$(grep "^NEW" "$changes_file" 2>/dev/null | wc -l)
        local deleted_count=$(grep "^DELETED" "$changes_file" 2>/dev/null | wc -l)
        local modified_count=$(grep "^MODIFIED" "$changes_file" 2>/dev/null | wc -l)

        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        local current_file_count=$(wc -l < "$current_state")

        if [[ $new_count -gt 0 || $deleted_count -gt 0 || $modified_count -gt 0 ]]; then
            echo "🔔 [$timestamp] Changes detected!"

            if ! $summary_only; then
                # Show detailed changes
                if [[ $new_count -gt 0 ]]; then
                    echo "  ✅ New files ($new_count):"
                    grep "^NEW" "$changes_file" | while IFS=$'\t' read -r action file size; do
                        echo "    + $(basename "$file") ($(format_size "$size"))"
                    done
                fi

                if [[ $deleted_count -gt 0 ]]; then
                    echo "  ❌ Deleted files ($deleted_count):"
                    grep "^DELETED" "$changes_file" | while IFS=$'\t' read -r action file _; do
                        echo "    - $(basename "$file")"
                    done
                fi

                if [[ $modified_count -gt 0 ]]; then
                    echo "  🔄 Modified files ($modified_count):"
                    grep "^MODIFIED" "$changes_file" | while IFS=$'\t' read -r action file size_change; do
                        echo "    ~ $(basename "$file") ($size_change)"
                    done
                fi
            else
                echo "  📊 Summary: +$new_count -$deleted_count ~$modified_count files"
            fi

            echo "  📂 Total files: $(printf "%'d" $current_file_count)"
            echo ""

            # Log to file if specified
            if [[ -n "$log_file" ]]; then
                {
                    echo "[$timestamp] +$new_count -$deleted_count ~$modified_count files (total: $current_file_count)"
                    if ! $summary_only; then
                        cat "$changes_file"
                    fi
                    echo ""
                } >> "$log_file"
            fi

            # Send webhook notification
            local webhook_msg="Bucket $bucket_path: +$new_count -$deleted_count"
            if $monitor_sizes && [[ $modified_count -gt 0 ]]; then
                webhook_msg="$webhook_msg ~$modified_count"
            fi
            webhook_msg="$webhook_msg files (total: $current_file_count)"
            send_webhook "$webhook_msg"

        else
            if [[ $((iteration % 10)) -eq 0 ]]; then
                echo "📊 [$timestamp] No changes ($(printf "%'d" $current_file_count) files)"
            fi
        fi
    done

    # Cleanup on exit
    trap "echo ''; echo '🛑 Monitoring stopped'; rm -rf '$temp_dir'; exit 0" INT TERM

    # Keep the script running
    wait
}

# Export function
export -f monitor_bucket

# Run directly if executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    monitor_bucket "$@"
fi
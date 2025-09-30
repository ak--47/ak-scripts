#!/bin/bash

# head_lines: Stream the first N lines from a cloud storage file to a new file
# Usage:
#   head_lines <source_file> [lines] [dest_file]
#
# Examples:
#   head_lines gs://bucket/data.json 1000
#   head_lines gs://bucket/data.json.gz 500 gs://bucket/data-sample.json.gz
#   head_lines gs://bucket/large-file.txt 100 gs://bucket/small-file.txt
#
# Notes:
# - Default lines: 1000
# - If dest_file not specified, uses ${source_file}-small.{ext}
# - Automatically detects and handles gzipped files (.gz extension)
# - Preserves compression for gzipped files (gzipped input -> gzipped output)

head_lines() {
    local source_file="$1"
    local lines="${2:-1000}"
    local dest_file="$3"

    # Validate input
    if [[ -z "$source_file" ]]; then
        echo "Usage: head_lines <source_file> [lines] [dest_file]"
        echo "Example: head_lines gs://bucket/data.json 1000"
        echo "Example: head_lines gs://bucket/data.json.gz 500 gs://bucket/sample.json.gz"
        return 1
    fi

    # Validate lines parameter
    if ! [[ "$lines" =~ ^[0-9]+$ ]] || [[ "$lines" -le 0 ]]; then
        echo "Error: lines must be a positive integer, got: $lines"
        return 1
    fi

    # Check if gsutil is available for GCS paths
    if [[ "$source_file" =~ ^gs:// ]] && ! command -v gsutil &> /dev/null; then
        echo "Error: gsutil is not installed or not in PATH"
        return 1
    fi

    # Check if aws CLI is available for S3 paths
    if [[ "$source_file" =~ ^s3:// ]] && ! command -v aws &> /dev/null; then
        echo "Error: aws CLI is not installed or not in PATH"
        return 1
    fi

    # Detect if source file is gzipped
    local is_gzipped=false
    if [[ "$source_file" =~ \.gz$ ]]; then
        is_gzipped=true
    fi

    # Generate destination file if not provided
    if [[ -z "$dest_file" ]]; then
        if $is_gzipped; then
            # Remove .gz, add -small, add .gz back
            dest_file="${source_file%.gz}-small.gz"
        else
            # Get extension and add -small before it
            local basename="${source_file%.*}"
            local extension="${source_file##*.}"
            if [[ "$basename" == "$source_file" ]]; then
                # No extension
                dest_file="${source_file}-small"
            else
                dest_file="${basename}-small.${extension}"
            fi
        fi
    fi

    echo "START"
    echo "Source: $source_file"
    echo "Destination: $dest_file"
    echo "Lines to extract: $(printf "%'d" $lines)"
    echo "Gzipped: $is_gzipped"
    echo ""

    # Verify source file exists
    local check_cmd
    if [[ "$source_file" =~ ^gs:// ]]; then
        check_cmd="gsutil ls '$source_file'"
    elif [[ "$source_file" =~ ^s3:// ]]; then
        check_cmd="aws s3 ls '$source_file'"
    else
        echo "Error: source file must be gs:// or s3://"
        return 1
    fi

    if ! eval "$check_cmd" &>/dev/null; then
        echo "Error: source file does not exist: $source_file"
        return 1
    fi

    # Create temporary file for processing
    local temp_dir=$(mktemp -d)
    local temp_file="$temp_dir/head_output"

    # Stream and process the file
    echo "Streaming first $lines lines..."

    local stream_cmd
    local upload_cmd

    if [[ "$source_file" =~ ^gs:// ]]; then
        if $is_gzipped; then
            # For gzipped files: stream, decompress, head, recompress
            stream_cmd="gsutil cat '$source_file' | gunzip | head -n $lines"
            if [[ "$dest_file" =~ \.gz$ ]]; then
                upload_cmd="gzip | gsutil cp - '$dest_file'"
            else
                upload_cmd="gsutil cp - '$dest_file'"
            fi
        else
            # For non-gzipped files: stream and head
            stream_cmd="gsutil cat '$source_file' | head -n $lines"
            if [[ "$dest_file" =~ \.gz$ ]]; then
                upload_cmd="gzip | gsutil cp - '$dest_file'"
            else
                upload_cmd="gsutil cp - '$dest_file'"
            fi
        fi
    elif [[ "$source_file" =~ ^s3:// ]]; then
        if $is_gzipped; then
            # For gzipped files: stream, decompress, head, recompress
            stream_cmd="aws s3 cp '$source_file' - | gunzip | head -n $lines"
            if [[ "$dest_file" =~ \.gz$ ]]; then
                upload_cmd="gzip | aws s3 cp - '$dest_file'"
            else
                upload_cmd="aws s3 cp - '$dest_file'"
            fi
        else
            # For non-gzipped files: stream and head
            stream_cmd="aws s3 cp '$source_file' - | head -n $lines"
            if [[ "$dest_file" =~ \.gz$ ]]; then
                upload_cmd="gzip | aws s3 cp - '$dest_file'"
            else
                upload_cmd="aws s3 cp - '$dest_file'"
            fi
        fi
    fi

    # Execute the pipeline
    local full_cmd="$stream_cmd | $upload_cmd"
    echo "Executing: $full_cmd"

    if eval "$full_cmd"; then
        echo ""
        echo "Success: Created $dest_file with first $lines lines"

        # Verify the output file was created
        local verify_cmd
        if [[ "$dest_file" =~ ^gs:// ]]; then
            verify_cmd="gsutil ls '$dest_file'"
        elif [[ "$dest_file" =~ ^s3:// ]]; then
            verify_cmd="aws s3 ls '$dest_file'"
        fi

        if eval "$verify_cmd" &>/dev/null; then
            echo "Verified: Output file exists"
        else
            echo "Warning: Could not verify output file creation"
        fi
    else
        echo "Error: Failed to create output file"
        rm -rf "$temp_dir"
        return 1
    fi

    # Cleanup
    rm -rf "$temp_dir"

    echo ""
    echo "DONE"
    return 0
}

# Make the function available for export
export -f head_lines

# If script is run directly (not sourced), execute with provided arguments
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    head_lines "$@"
fi
#!/bin/bash

# copy_bucket: Copy or mirror objects between cloud storage locations (GCS/S3)
# Usage:
#   copy_bucket <src...> <dest>
#   copy_bucket --mirror [--dry-run] <src> <dest>
# 
# Examples:
#   # Copy multiple patterns to a dest (fast, parallel)
#   copy_bucket 'gs://bucket/src/prefix/*.json' gs://bucket/dest/
#   copy_bucket 'gs://a/prefix/file1.json' 'gs://a/prefix/file2.json' gs://b/dest/
# 
#   # Mirror (rsync) a source to dest and delete extras in dest
#   copy_bucket --mirror gs://posthog_to_mixpanel_teachy_final gs://teachy-posthog
#   copy_bucket --mirror --dry-run gs://posthog_to_mixpanel_teachy_final gs://teachy-posthog
#
# Notes:
# - --dry-run only applies to --mirror mode (rsync supports -n). There is no dry-run for cp.
# - For S3, you need AWS CLI installed. For GCS, you need gsutil installed.

copy_bucket() {
    if [[ "$#" -lt 2 ]]; then
        echo "Usage: copy_bucket <src...> <dest>"
        echo "       copy_bucket --mirror [--dry-run] <src> <dest>"
        echo ""
        echo "Examples:"
        echo "  copy_bucket 'gs://bucket/src/*.json' gs://bucket/dest/"
        echo "  copy_bucket --mirror gs://src-bucket/path gs://dest-bucket/path"
        echo "  copy_bucket --mirror --dry-run gs://src gs://dest"
        return 1
    fi

    local mirror=false
    local dry_run=false
    local args=()

    # Parse flags
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --mirror)
                mirror=true; shift ;;
            --dry-run)
                dry_run=true; shift ;;
            --)
                shift; break ;;
            -*)
                echo "Unknown option: $1"; return 1 ;;
            *)
                args+=("$1"); shift ;;
        esac
    done

    # Append remaining positional args
    while [[ "$#" -gt 0 ]]; do args+=("$1"); shift; done

    if $mirror; then
        if [[ ${#args[@]} -ne 2 ]]; then
            echo "Error: --mirror requires exactly <src> and <dest>"
            return 1
        fi
        local src="${args[0]}"
        local dest="${args[1]}"

        if [[ "$src" != gs://* && "$src" != s3://* ]]; then
            echo "Error: src must be gs:// or s3://"
            return 1
        fi
        if [[ "$dest" != gs://* && "$dest" != s3://* ]]; then
            echo "Error: dest must be gs:// or s3://"
            return 1
        fi

        # Mirror via rsync
        if [[ "$src" == gs://* ]]; then
            local flags="-m rsync -r -d"
            if $dry_run; then flags="-m rsync -n -r -d"; fi
            echo "Running: gsutil $flags '$src' '$dest'"
            gsutil $flags "$src" "$dest"
        else
            # S3 mirror using aws s3 sync
            local flags="s3 sync --delete"
            if $dry_run; then flags="s3 sync --delete --dryrun"; fi
            echo "Running: aws $flags '$src' '$dest'"
            aws $flags "$src" "$dest"
        fi
        return $?
    fi

    # Copy mode (sources then dest as last arg)
    if [[ ${#args[@]} -lt 2 ]]; then
        echo "Error: copy mode requires at least one src and a dest"
        return 1
    fi

    local dest="${args[-1]}"
    unset 'args[${#args[@]}]'

    # Determine backend by first src
    local first_src="${args[0]}"
    if [[ "$first_src" == gs://* ]]; then
        echo "Running: gsutil -m cp [${#args[@]} srcs] -> $dest"
        gsutil -m cp "${args[@]}" "$dest"
        return $?
    elif [[ "$first_src" == s3://* ]]; then
        echo "Running: aws s3 cp --recursive/parallel [${#args[@]} srcs] -> $dest"
        # aws s3 cp doesn't accept multiple srcs; loop them in parallel
        printf '%s
' "${args[@]}" | xargs -I {} -P 16 sh -c 'aws s3 cp "$1" "$2" --recursive 2>&1' _ {} "$dest"
        return $?
    else
        echo "Error: src must be gs:// or s3://"
        return 1
    fi
}

export -f copy_bucket

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    copy_bucket "$@"
fi

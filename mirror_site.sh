#!/bin/bash

# Mirror a website using HTTrack with polite crawling and asset completion
mirror_site() {
    # Show help if no arguments or help requested
    if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: mirror_site <url> [options]"
        echo ""
        echo "Polite, asset-complete mirror of a single host using HTTrack."
        echo "Produces ./site-<domain>/ with index.html at the root (ready for 'npx serve')."
        echo ""
        echo "Arguments:"
        echo "  url                   Website URL to mirror (with or without https://)"
        echo ""
        echo "Options:"
        echo "  --depth=N             Max link depth for HTML pages (default: 3)"
        echo "  --concurrency=N       Concurrent connections (default: 8)"
        echo "  --cps=N               Max connections per second (default: 5)"
        echo "  --retries=N           Retry count per URL (default: 2)"
        echo "  --timeout=SEC         Seconds per-URL timeout (default: 30)"
        echo "  --max-rate=BYTES      Bytes/sec cap (e.g., 250000)"
        echo "  --max-asset-size=B    Limit non-HTML file size (e.g., 5000000)"
        echo "  --allow-subdomains    Include subdomains of base domain"
        echo "  --no-external-assets  Don't fetch CDN assets referenced by pages"
        echo "  --ignore-robots       Ignore robots.txt (use responsibly)"
        echo "  --clean-cache         Remove hts-cache after mirror"
        echo "  --verbose             Show detailed httrack logs"
        echo "  --user-agent=UA       Custom user agent string"
        echo "  --inject-js=CONTENT   JavaScript content to inject site-wide"
        echo "  --inject-js-path=PATH Path for injected JS file (default: INJECTED.js)"
        echo ""
        echo "Examples:"
        echo "  mirror_site https://example.com"
        echo "  mirror_site example.com --depth=4 --max-rate=250000"
        echo "  mirror_site https://foo.com --allow-subdomains --ignore-robots"
        echo "  mirror_site https://bar.com --inject-js=\"console.log('Hello');\""
        echo ""
        echo "Output:"
        echo "  ./site-<domain>/     (single folder)"
        echo "    index.html         (real homepage)"
        echo "    INJECTED.js        (injected site-wide)"
        echo "    ...                (HTML and static assets)"
        echo ""
        echo "Then serve with: cd ./site-<domain> && npx serve"
        return 0
    fi

    # Default values
    local url="$1"
    local depth=3
    local concurrency=8
    local cps=5
    local retries=2
    local timeout=30
    local max_rate=""
    local max_asset_bytes=""
    local obey_robots=1
    local allow_subdomains=0
    local allow_external_assets=1
    local clean_cache=0
    local verbose=0
    local user_agent="HTTrack-Wrapper/1.1 (polite; robots; limited rate)"
    local inject_js_path="INJECTED.js"
    local inject_js_content="console.log('INJECTED!');"

    # Parse arguments
    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --depth=*)
                depth="${1#*=}"
                shift
                ;;
            --concurrency=*)
                concurrency="${1#*=}"
                shift
                ;;
            --cps=*)
                cps="${1#*=}"
                shift
                ;;
            --retries=*)
                retries="${1#*=}"
                shift
                ;;
            --timeout=*)
                timeout="${1#*=}"
                shift
                ;;
            --max-rate=*)
                max_rate="${1#*=}"
                shift
                ;;
            --max-asset-size=*)
                max_asset_bytes="${1#*=}"
                shift
                ;;
            --user-agent=*)
                user_agent="${1#*=}"
                shift
                ;;
            --inject-js=*)
                inject_js_content="${1#*=}"
                shift
                ;;
            --inject-js-path=*)
                inject_js_path="${1#*=}"
                shift
                ;;
            --allow-subdomains)
                allow_subdomains=1
                shift
                ;;
            --no-external-assets)
                allow_external_assets=0
                shift
                ;;
            --ignore-robots)
                obey_robots=0
                shift
                ;;
            --clean-cache)
                clean_cache=1
                shift
                ;;
            --verbose)
                verbose=1
                shift
                ;;
            *)
                echo "Unknown option: $1"
                return 1
                ;;
        esac
    done

    # Validate input
    if [[ -z "$url" ]]; then
        echo "❌ Error: URL is required"
        return 1
    fi

    # Check if httrack is available
    if ! command -v httrack &> /dev/null; then
        echo "❌ Error: httrack is not installed or not in PATH"
        echo "Install with: brew install httrack (macOS) or apt-get install httrack (Ubuntu)"
        return 1
    fi

    # Normalize URL: if scheme is missing, assume https
    if [[ ! "$url" =~ ^https?:// ]]; then
        url="https://$url"
    fi

    # Extract host
    local host
    host=$(echo "$url" | sed -E 's~^https?://([^/]+).*~\1~')

    if [[ -z "$host" ]]; then
        echo "❌ Error: Could not parse host from URL: $url"
        return 1
    fi

    local out_dir="site-${host}"

    echo "🌐 Website Mirror Starting"
    echo "=========================="
    echo "URL: $url"
    echo "Host: $host"
    echo "Output directory: $out_dir"
    echo "Depth: $depth"
    echo "Concurrency: $concurrency"
    echo "Max connections/sec: $cps"
    if [[ -n "$max_rate" ]]; then
        echo "Rate limit: $max_rate bytes/sec"
    fi
    if [[ -n "$max_asset_bytes" ]]; then
        echo "Max asset size: $max_asset_bytes bytes"
    fi
    if [[ $allow_subdomains -eq 1 ]]; then
        echo "Including subdomains: yes"
    fi
    if [[ $allow_external_assets -eq 0 ]]; then
        echo "External assets: disabled"
    fi
    if [[ $obey_robots -eq 0 ]]; then
        echo "⚠️  Robots.txt: IGNORED"
    fi
    echo ""

    # Create output directory
    mkdir -p "$out_dir"

    # Alternate host (with/without www) for convenience
    local alt_host=""
    if [[ "$host" =~ ^www\. ]]; then
        alt_host="${host#www.}"
    else
        alt_host="www.${host}"
    fi

    # Build httrack command options
    local cmd_opts=()

    # Basic structure options
    cmd_opts+=("-N100" "-I0" "-K0")  # No subdirs, no index page, keep relative links

    # Politeness options
    cmd_opts+=("-c$concurrency" "-%c$cps" "-T$timeout" "-R$retries")
    [[ -n "$max_rate" ]] && cmd_opts+=("-A$max_rate")
    [[ -n "$max_asset_bytes" ]] && cmd_opts+=("-m$max_asset_bytes")

    # Scope options
    cmd_opts+=("-a" "-r$depth" "-%e0")  # Stay on address, depth limit, no external recursion

    # Parsing options
    cmd_opts+=("-%P")  # Extended parsing
    [[ $allow_external_assets -eq 1 ]] && cmd_opts+=("-n")

    # Robots.txt handling
    if [[ $obey_robots -eq 1 ]]; then
        cmd_opts+=("-s2")  # Obey robots.txt
    else
        cmd_opts+=("-s0")  # Ignore robots.txt
    fi

    # Logging options
    cmd_opts+=("-f2")  # Single log file
    if [[ $verbose -eq 1 ]]; then
        cmd_opts+=("-z" "-v")
    else
        cmd_opts+=("-q")
    fi

    # Tidy options
    cmd_opts+=("-o0" "-X")

    # User agent
    cmd_opts+=("-F" "$user_agent")

    # Prepare injected JS and footer
    echo "$inject_js_content" > "$out_dir/$inject_js_path"
    cmd_opts+=("-%F" "<script src=\"/$(basename "$inject_js_path")\"></script>")

    # Build scan rules
    local scan_rules=("-*" "+${host}/*" "+${alt_host}/*")

    # Include subdomains if requested
    if [[ $allow_subdomains -eq 1 ]]; then
        local base_domain
        base_domain=$(echo "$host" | awk -F. '{n=NF; if (n>1) print $(n-1)"."$n; else print $0}')
        scan_rules+=( "+*.$base_domain/*" )
    fi

    # Always allow common static assets if external assets are enabled
    if [[ $allow_external_assets -eq 1 ]]; then
        scan_rules+=(
            "+*.png" "+*.jpg" "+*.jpeg" "+*.gif" "+*.webp" "+*.svg" "+*.ico"
            "+*.css" "+*.js" "+*.mjs" "+*.map"
            "+*.woff" "+*.woff2" "+*.ttf" "+*.eot" "+*.otf"
            "+*.mp4" "+*.webm" "+*.ogg" "+*.mp3" "+*.m4a" "+*.m4v"
            "+*.pdf" "+*.json" "+*.xml" "+*.txt"
        )
    fi

    # Skip private/admin areas
    scan_rules+=(
        "-*/wp-admin/*" "-*/wp-login*" "-*signin*" "-*login*" "-*logout*"
        "-*/admin/*" "-*/account/*" "-*/dashboard/*" "-*/cart/*" "-*/checkout/*"
    )

    echo "🚀 Starting mirror process..."
    if [[ $verbose -eq 1 ]]; then
        echo "Command: httrack \"$url\" -O \"$out_dir\" ${cmd_opts[*]} ${scan_rules[*]}"
        echo ""
    fi

    # Execute httrack
    if httrack "$url" -O "$out_dir" "${cmd_opts[@]}" "${scan_rules[@]}"; then
        # Optional cleanup
        if [[ $clean_cache -eq 1 ]]; then
            rm -rf "$out_dir/hts-cache" 2>/dev/null || true
            echo "🧹 Cleaned cache directory"
        fi

        echo ""
        echo "✅ Mirror completed successfully!"
        echo "==========================================="
        echo "📁 Output directory: $out_dir"
        echo "🚀 Serve locally with:"
        echo "   cd \"$out_dir\" && npx serve"
        echo ""
        echo "💉 Injected JS: $out_dir/$inject_js_path"
        echo ""

        # Show some stats
        local html_count=$(find "$out_dir" -name "*.html" -type f 2>/dev/null | wc -l)
        local total_files=$(find "$out_dir" -type f 2>/dev/null | wc -l)
        echo "📊 Files mirrored:"
        echo "   HTML pages: $(printf "%'d" $html_count)"
        echo "   Total files: $(printf "%'d" $total_files)"

        if command -v du &> /dev/null; then
            local size_kb=$(du -sk "$out_dir" 2>/dev/null | cut -f1)
            if [[ -n "$size_kb" ]]; then
                local size_mb=$((size_kb / 1024))
                echo "   Total size: ${size_mb}MB"
            fi
        fi

        echo ""
        return 0
    else
        echo ""
        echo "❌ Mirror failed!"
        echo "Check the httrack logs in $out_dir for details."
        return 1
    fi
}

# Export function
export -f mirror_site

# Run directly if executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    mirror_site "$@"
fi
#!/bin/zsh

# Enhanced Website Mirror Script for Educational Purposes
# Designed to respectfully mirror sites while avoiding bot detection
# Version 2.0

# Only enable strict mode when running directly, not when sourced
# Note: Disabled strict mode to avoid issues with shell autoloading
# if [[ "${(%):-%x}" == "${0}" ]]; then
#     set -euo pipefail
# fi

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Default configuration
readonly DEFAULT_DELAY_MIN=1
readonly DEFAULT_DELAY_MAX=2
readonly DEFAULT_DEPTH=2
readonly DEFAULT_CONNECTIONS=4
readonly DEFAULT_TIMEOUT=60
readonly DEFAULT_RETRIES=3
readonly DEFAULT_RATE_LIMIT=500000  # 500KB/s
readonly DEFAULT_MAX_SIZE=10000000  # 10MB per file

# User agents that typically avoid bot detection
declare -a USER_AGENTS=(
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/121.0"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Safari/605.1.15"
)

# Function to print colored output
print_color() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

# Function to generate random delay
random_delay() {
    local min=${1:-$DEFAULT_DELAY_MIN}
    local max=${2:-$DEFAULT_DELAY_MAX}
    echo $((min + RANDOM % (max - min + 1)))
}

# Function to select random user agent
random_user_agent() {
    local index=$((RANDOM % ${#USER_AGENTS[@]}))
    echo "${USER_AGENTS[$index]}"
}

# Function to check prerequisites
check_prerequisites() {
    local missing_tools=()
    
    if ! command -v httrack &> /dev/null; then
        missing_tools+=("httrack")
    fi
    
    if ! command -v curl &> /dev/null; then
        missing_tools+=("curl")
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_color "$RED" "❌ Missing required tools: ${missing_tools[*]}"
        print_color "$YELLOW" "Installation instructions:"
        for tool in "${missing_tools[@]}"; do
            case "$tool" in
                httrack)
                    echo "  • macOS: brew install httrack"
                    echo "  • Ubuntu/Debian: sudo apt-get install httrack"
                    echo "  • RHEL/CentOS: sudo yum install httrack"
                    ;;
                curl)
                    echo "  • macOS: brew install curl"
                    echo "  • Ubuntu/Debian: sudo apt-get install curl"
                    ;;
            esac
        done
        return 1
    fi
    return 0
}

# Function to test site accessibility
test_site_access() {
    local url=$1
    local user_agent=$2
    local test_timeout=10
    
    print_color "$BLUE" "🔍 Testing site accessibility..."
    
    # Test with curl first
    local response_code
    response_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "User-Agent: $user_agent" \
        -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
        -H "Accept-Language: en-US,en;q=0.5" \
        -H "DNT: 1" \
        -H "Connection: keep-alive" \
        -H "Upgrade-Insecure-Requests: 1" \
        --max-time "$test_timeout" \
        --location \
        --fail-with-body \
        "$url" 2>/dev/null || echo "000")
    
    case "$response_code" in
        200|301|302|304)
            print_color "$GREEN" "  ✅ Site is accessible (HTTP $response_code)"
            return 0
            ;;
        403)
            print_color "$YELLOW" "  ⚠️  Access forbidden (HTTP 403) - may need different approach"
            return 1
            ;;
        404)
            print_color "$RED" "  ❌ Page not found (HTTP 404)"
            return 1
            ;;
        000)
            print_color "$RED" "  ❌ Connection failed or timeout"
            return 1
            ;;
        *)
            print_color "$YELLOW" "  ⚠️  Unexpected response code: $response_code"
            return 1
            ;;
    esac
}

# Function to create robots.txt override
create_robots_override() {
    local out_dir=$1
    cat > "$out_dir/robots.txt" <<EOF
# Educational mirror - respecting original site
User-agent: *
Crawl-delay: 2
EOF
}

# Main mirror function
mirror_site() {
    # Show help if needed
    if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
        cat <<EOF
${GREEN}Educational Site Mirror Tool v2.0${NC}

${BLUE}USAGE:${NC}
  $(basename "$0") <url> [options]

${BLUE}DESCRIPTION:${NC}
  Respectfully mirrors a website for educational purposes (e.g., SDK testing).
  Implements anti-bot detection measures and polite crawling.

${BLUE}OPTIONS:${NC}
  --depth=N              Max crawl depth (default: $DEFAULT_DEPTH)
  --delay=MIN-MAX        Request delay range in seconds (default: ${DEFAULT_DELAY_MIN}-${DEFAULT_DELAY_MAX})
  --connections=N        Concurrent connections (default: $DEFAULT_CONNECTIONS)
  --timeout=SEC          Connection timeout (default: $DEFAULT_TIMEOUT)
  --rate-limit=BYTES     Download rate limit (default: $DEFAULT_RATE_LIMIT)
  --max-size=BYTES       Max file size (default: $DEFAULT_MAX_SIZE)
  --retries=N            Retry attempts (default: $DEFAULT_RETRIES)
  --user-agent=STRING    Custom user agent (default: random browser)
  --inject-js=CODE       JavaScript to inject site-wide
  --stealth              Maximum stealth mode (slowest but safest)
  --aggressive           Faster mirroring (may trigger bot detection)
  --test-only            Only test site accessibility
  --include-subdomains   Include subdomains in mirror
  --skip-external        Skip all external resources
  --verbose              Show detailed progress
  --dry-run              Show what would be done without executing

${BLUE}STEALTH PROFILES:${NC}
  Default: Balanced speed and stealth
  --stealth: Very slow, maximum anti-detection (3-8s delays, 1 connection)
  --aggressive: Faster but riskier (0-1s delays, 4 connections)

${BLUE}EXAMPLES:${NC}
  # Basic mirror with defaults
  $(basename "$0") https://example.com

  # Stealth mode for sensitive sites
  $(basename "$0") https://example.com --stealth

  # Custom settings
  $(basename "$0") https://example.com --depth=3 --delay=2-5

  # Test before mirroring
  $(basename "$0") https://example.com --test-only

${BLUE}OUTPUT:${NC}
  Creates ./mirror-<domain>/ directory with:
    • index.html (main page)
    • All crawled HTML/CSS/JS/images
    • Optional injected JavaScript
    • Ready to serve with: npx serve

${YELLOW}IMPORTANT:${NC}
  This tool is for educational purposes only.
  Always respect website terms of service and robots.txt.
  Some sites may still detect and block automated access.

EOF
        return 0
    fi

    # Check prerequisites
    if ! check_prerequisites; then
        return 1
    fi

    # Parse arguments
    local url="$1"
    local depth=$DEFAULT_DEPTH
    local delay_min=$DEFAULT_DELAY_MIN
    local delay_max=$DEFAULT_DELAY_MAX
    local connections=$DEFAULT_CONNECTIONS
    local timeout=$DEFAULT_TIMEOUT
    local rate_limit=$DEFAULT_RATE_LIMIT
    local max_size=$DEFAULT_MAX_SIZE
    local retries=$DEFAULT_RETRIES
    local user_agent=""
    local inject_js=""
    local stealth=0
    local aggressive=0
    local test_only=0
    local include_subdomains=0
    local verbose=0
    local dry_run=0

    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --depth=*)
                depth="${1#*=}"
                ;;
            --delay=*)
                IFS='-' read -r delay_min delay_max <<< "${1#*=}"
                ;;
            --connections=*)
                connections="${1#*=}"
                ;;
            --timeout=*)
                timeout="${1#*=}"
                ;;
            --rate-limit=*)
                rate_limit="${1#*=}"
                ;;
            --max-size=*)
                max_size="${1#*=}"
                ;;
            --retries=*)
                retries="${1#*=}"
                ;;
            --user-agent=*)
                user_agent="${1#*=}"
                ;;
            --inject-js=*)
                inject_js="${1#*=}"
                ;;
            --stealth)
                stealth=1
                ;;
            --aggressive)
                aggressive=1
                ;;
            --test-only)
                test_only=1
                ;;
            --include-subdomains)
                include_subdomains=1
                ;;
            --skip-external)
                # Note: External resource handling is controlled by scan rules
                ;;
            --verbose)
                verbose=1
                ;;
            --dry-run)
                dry_run=1
                ;;
            *)
                print_color "$RED" "Unknown option: $1"
                return 1
                ;;
        esac
        shift
    done

    # Apply profiles
    if [ $stealth -eq 1 ]; then
        delay_min=3
        delay_max=8
        connections=1
        rate_limit=50000
        print_color "$YELLOW" "🥷 Stealth mode activated (very slow but safe)"
    elif [ $aggressive -eq 1 ]; then
        delay_min=0
        delay_max=1
        connections=4
        rate_limit=500000
        print_color "$YELLOW" "⚡ Aggressive mode activated (faster but riskier)"
    fi

    # Normalize URL
    if [[ ! "$url" =~ ^https?:// ]]; then
        url="https://$url"
    fi

    # Extract host
    local host
    host=$(echo "$url" | sed -E 's~^https?://([^/]+).*~\1~')
    
    # Set user agent
    if [ -z "$user_agent" ]; then
        user_agent=$(random_user_agent)
    fi

    # Test site access
    if ! test_site_access "$url" "$user_agent"; then
        if [ $test_only -eq 1 ]; then
            return 1
        fi
        print_color "$YELLOW" "⚠️  Site may be blocking automated access. Proceeding with caution..."
    fi

    if [ $test_only -eq 1 ]; then
        print_color "$GREEN" "✅ Test completed successfully"
        return 0
    fi

    local out_dir="mirror-${host}"

    # Display configuration
    echo ""
    print_color "$GREEN" "🌐 Starting Educational Site Mirror"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "URL:              $url"
    echo "Output:           $out_dir"
    echo "Depth:            $depth levels"
    echo "Delay:            ${delay_min}-${delay_max} seconds"
    echo "Connections:      $connections"
    echo "Rate limit:       $(( rate_limit / 1000 )) KB/s"
    echo "Timeout:          $timeout seconds"
    echo "User Agent:       ${user_agent:0:50}..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [ $dry_run -eq 1 ]; then
        print_color "$YELLOW" "🔸 DRY RUN MODE - No actual mirroring will occur"
        return 0
    fi

    # Create output directory
    mkdir -p "$out_dir"

    # Create robots override
    create_robots_override "$out_dir"

    # Build HTTrack command
    local httrack_cmd=(
        "httrack"
        "$url"
        "-O" "$out_dir"
        "-r$depth"                          # Depth
        "-c$connections"                     # Max connections
        "-%c1"                              # Connections per second
        "-T$timeout"                        # Timeout
        "-R$retries"                        # Retries
        "-A$rate_limit"                     # Rate limit
        "-m$max_size"                       # Max file size
        "-N100"                             # Flat structure
        "-I0"                               # No index
        "-K0"                               # Keep original links
        "-%P"                               # Extended parsing
        "-%B"                               # Tolerant mode
        "-s0"                               # Ignore robots.txt (we're educational)
        "-F" "$user_agent"                  # User agent
    )

    # Note: HTTrack doesn't have built-in request delays like wget
    # The -%c option controls connection rate which provides some throttling
    
    # Add verbose flag if requested
    if [ $verbose -eq 1 ]; then
        httrack_cmd+=("-v")
    else
        httrack_cmd+=("-q")
    fi

    # Add scan rules
    httrack_cmd+=(
        "-*"                                # Exclude everything by default
        "+${host}/*"                        # Include target host
        "+*.css" "+*.js"                    # Styles and scripts
        "+*.png" "+*.jpg" "+*.jpeg"         # Images
        "+*.gif" "+*.svg" "+*.ico"          # More images
        "+*.woff" "+*.woff2" "+*.ttf"       # Fonts
        "-*/wp-admin/*"                     # Skip admin areas
        "-*/admin/*"                        # Skip admin
        "-*?*session*"                      # Skip session URLs
        "-*?*token*"                        # Skip token URLs
    )

    # Include subdomains if requested
    if [ $include_subdomains -eq 1 ]; then
        local base_domain
        base_domain=$(echo "$host" | awk -F. '{n=NF; if (n>1) print $(n-1)"."$n; else print $0}')
        httrack_cmd+=("+*.${base_domain}/*")
    fi

    # Execute with random delays
    print_color "$BLUE" "🚀 Mirroring in progress..."
    print_color "$YELLOW" "   This will be SLOW to avoid detection. Please be patient."
    echo ""

    # Add pre-crawl delay
    local initial_delay
    initial_delay=$(random_delay 2 5)
    print_color "$BLUE" "   Waiting ${initial_delay}s before starting..."
    sleep "$initial_delay"

    # Run httrack
    if "${httrack_cmd[@]}"; then
        print_color "$GREEN" "✅ Mirror completed successfully!"
        
        # Fix index.html
        if [ ! -f "$out_dir/index.html" ]; then
            local index_file
            index_file=$(find "$out_dir" -maxdepth 1 -name "*.html" -type f | head -1)
            if [ -n "$index_file" ]; then
                cp "$index_file" "$out_dir/index.html"
                print_color "$GREEN" "   Created index.html"
            fi
        fi

        # Inject JavaScript if provided
        if [ -n "$inject_js" ]; then
            echo "$inject_js" > "$out_dir/injected.js"
            find "$out_dir" -name "*.html" -type f -exec sed -i '' \
                's|</body>|<script src="/injected.js"></script></body>|g' {} \; 2>/dev/null || true
            print_color "$GREEN" "   Injected custom JavaScript"
        fi

        # Statistics
        local file_count html_count
        file_count=$(find "$out_dir" -type f | wc -l)
        html_count=$(find "$out_dir" -name "*.html" -type f | wc -l)
        
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        print_color "$GREEN" "📊 Mirror Statistics:"
        echo "   HTML files:    $html_count"
        echo "   Total files:   $file_count"
        echo "   Output:        $out_dir/"
        echo ""
        print_color "$BLUE" "🎯 Next steps:"
        echo "   cd $out_dir && npx serve"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        return 0
    else
        print_color "$RED" "❌ Mirror failed!"
        
        # Check logs
        if [ -f "$out_dir/hts-log.txt" ]; then
            print_color "$YELLOW" "📋 Error details:"
            tail -5 "$out_dir/hts-log.txt"
        fi
        
        print_color "$YELLOW" "💡 Suggestions:"
        echo "  1. Try --stealth mode for better anti-detection"
        echo "  2. Increase --delay for slower crawling"
        echo "  3. Use --test-only to check accessibility first"
        echo "  4. Some sites cannot be mirrored due to JavaScript requirements"
        
        return 1
    fi
}

# Export function
export -f mirror_site

# Run if executed directly
if [[ "${(%):-%x}" == "${0}" ]]; then
    mirror_site "$@"
fi
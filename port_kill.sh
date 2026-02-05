#!/bin/bash

# port_kill: Kill process using a specific port
# Usage:
#   port_kill <port>
#
# Examples:
#   port_kill 3000
#   port_kill 8080
#
# Notes:
# - Requires a port number as argument
# - Finds and kills the process listening on the specified port
# - Uses lsof to identify the process

port_kill() {
    local port="$1"

    # Show help if no arguments or help requested
    if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: port_kill <port>"
        echo ""
        echo "Kill the process using the specified port."
        echo ""
        echo "Arguments:"
        echo "  port  Port number to search for"
        echo ""
        echo "Examples:"
        echo "  port_kill 3000"
        echo "  port_kill 8080"
        return 0
    fi

    # Validate input
    if [[ -z "$port" ]]; then
        echo "❌ Error: Port number is required"
        echo "Usage: port_kill <port>"
        return 1
    fi

    # Validate port is a number
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        echo "❌ Error: Port must be a number, got: $port"
        return 1
    fi

    # Validate port range
    if [[ "$port" -lt 1 || "$port" -gt 65535 ]]; then
        echo "❌ Error: Port must be between 1 and 65535, got: $port"
        return 1
    fi

    # Find process using the port
    echo "🔍 Searching for process on port $port..."
    
    local pid=$(lsof -ti :$port)

    if [[ -z "$pid" ]]; then
        echo "❌ No process found on port $port"
        return 1
    fi

    # Get process details
    local process_info=$(ps -p $pid -o comm= 2>/dev/null)
    
    echo "📍 Found process: $process_info (PID: $pid)"
    echo "🔪 Killing process..."

    # Kill the process
    if kill $pid 2>/dev/null; then
        echo "✅ Successfully killed process on port $port"
        return 0
    else
        echo "⚠️  Failed to kill with SIGTERM, trying SIGKILL..."
        if kill -9 $pid 2>/dev/null; then
            echo "✅ Successfully force-killed process on port $port"
            return 0
        else
            echo "❌ Failed to kill process. You may need sudo privileges."
            return 1
        fi
    fi
}

# Export function
export -f port_kill

# Run directly if executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    port_kill "$@"
fi

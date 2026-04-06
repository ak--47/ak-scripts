#!/bin/bash

# Ask Claude a question from the terminal
# Streams the response to stdout with web search enabled

ask_c() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: ask_c <prompt>"
        echo "  Sends prompt to Claude (claude-sonnet-4-6) with web search"
        echo "  Streams the response to stdout"
        echo ""
        echo "  Environment:"
        echo "    MODEL    Override the default model (e.g., MODEL=claude-opus-4-6 ask_c <prompt>)"
        return 0
    fi

    if [[ $# -eq 0 ]]; then
        echo "❌ No prompt provided. Usage: ask_c <prompt>" >&2
        return 1
    fi

    (cd /Users/ak/code/ak-ai-wrappers/ak-claude && node cli.js "$*")
}

export -f ask_c

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    ask_c "$@"
fi

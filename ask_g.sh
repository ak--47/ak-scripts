#!/bin/bash

# Ask Gemini a question from the terminal
# Streams the response to stdout with Google Search grounding enabled

ask_g() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: ask_g <prompt>"
        echo "  Sends prompt to Gemini (gemini-3.1-flash-lite-preview) with Google Search grounding"
        echo "  Streams the response to stdout"
        echo ""
        echo "  Environment:"
        echo "    MODEL    Override the default model (e.g., MODEL=gemini-2.5-pro ask_g <prompt>)"
        return 0
    fi

    if [[ $# -eq 0 ]]; then
        echo "❌ No prompt provided. Usage: ask_g <prompt>" >&2
        return 1
    fi

    (cd /Users/ak/code/ak-ai-wrappers/ak-gemini && node cli.js "$*")
}

export -f ask_g

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    ask_g "$@"
fi

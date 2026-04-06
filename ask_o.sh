#!/bin/bash

# Ask GPT (OpenAI) a question from the terminal
# Streams the response to stdout with web search enabled

ask_o() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: ask_o <prompt>"
        echo "  Sends prompt to GPT (gpt-4o) with web search"
        echo "  Streams the response to stdout"
        echo ""
        echo "  Environment:"
        echo "    MODEL    Override the default model (e.g., MODEL=gpt-4.1 ask_o <prompt>)"
        return 0
    fi

    if [[ $# -eq 0 ]]; then
        echo "❌ No prompt provided. Usage: ask_o <prompt>" >&2
        return 1
    fi

    (cd /Users/ak/code/ak-ai-wrappers/ak-gpt && node cli.js "$*")
}

export -f ask_o

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    ask_o "$@"
fi

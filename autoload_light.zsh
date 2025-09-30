#!/bin/zsh

# Lightweight Script Auto-loader for Zsh (Warp-optimized)
# This file sets up simple aliases for all .sh files in ~/scripts/
# Add this ONE line to your ~/.zshrc:
# source ~/scripts/autoload_light.zsh

# Set default values for variables that Warp terminal expects
export POWERLEVEL9K_PROMPT_ADD_NEWLINE=${POWERLEVEL9K_PROMPT_ADD_NEWLINE:-false}
export INSIDE_EMACS=${INSIDE_EMACS:-""}
export vi_mode_in_opts=${vi_mode_in_opts:-""}

# Get the scripts directory
export SCRIPTS_DIR="$HOME/scripts"

# Quick check if scripts directory exists
[[ ! -d "$SCRIPTS_DIR" ]] && return 1

# Create simple aliases for all scripts (no heavy processing)
loaded_count=0
for script_file in "$SCRIPTS_DIR"/*.sh; do
    [[ -f "$script_file" ]] || continue
    script_name=$(basename "$script_file" .sh)
    alias "$script_name"="bash $script_file"
    ((loaded_count++))
done

# Add scripts directory to PATH
export PATH="$SCRIPTS_DIR:$PATH"

# Helper function to list all loaded scripts (lazy version)
list_scripts() {
    echo "📜 Available Scripts in ~/scripts/:"
    echo "=================================="
    echo ""

    for script_file in "$HOME/scripts"/*.sh; do
        [[ -f "$script_file" ]] || continue
        local script_name=$(basename "$script_file" .sh)
        local file_size=$(ls -lh "$script_file" | awk '{print $5}')
        echo "📄 $script_name (script, $file_size)"
    done

    echo ""
    echo "💡 Run any script name without arguments to see usage help."
}

# Make the helper function available
export -f list_scripts

# Show quick success message
echo "🚀 Auto-loaded $loaded_count scripts from ~/scripts/ - run 'list_scripts' to see all"
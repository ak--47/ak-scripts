#!/bin/bash

# Dynamic Script Auto-loader for Bash
# This file automatically loads all .sh files in ~/scripts/ as functions
# Add this ONE line to your ~/.bashrc:
# source ~/scripts/autoload.bash

# Get the scripts directory
export SCRIPTS_DIR="$HOME/scripts"

# Check if scripts directory exists
if [[ ! -d "$SCRIPTS_DIR" ]]; then
    echo "Warning: ~/scripts directory not found"
    return 1
fi

# Counter for loaded scripts
loaded_count=0

# Auto-load all .sh files in ~/scripts/
for script_file in "$SCRIPTS_DIR"/*.sh; do
    # Skip if no .sh files found (glob doesn't match)
    [[ -f "$script_file" ]] || continue

    # Get the base filename without path and extension
    script_name=$(basename "$script_file" .sh)

    # Try to source the script to load its functions
    if bash -c "source '$script_file'; declare -f '$script_name'" >/dev/null 2>&1; then
        # Script has a function with matching name, source it in bash
        if source "$script_file" 2>/dev/null; then
            ((loaded_count++))
        else
            # Failed to source, create alias
            alias "$script_name"="bash $script_file"
            ((loaded_count++))
        fi

        # Create an alias that calls the main function
        if declare -f "$script_name" >/dev/null 2>&1; then
            alias "$script_name"="$script_name"
        else
            # Function didn't load properly, create script alias
            alias "$script_name"="bash $script_file"
        fi
    else
        # No matching function, create a wrapper that runs the script directly
        alias "$script_name"="bash $script_file"
        ((loaded_count++))
    fi
done

# Add scripts directory to PATH for direct execution
export PATH="$SCRIPTS_DIR:$PATH"

# Helper function to list all loaded scripts
list_scripts() {
    echo "Available Scripts in ~/scripts/:"
    echo "=================================="
    echo ""

    for script_file in "$HOME/scripts"/*.sh; do
        [[ -f "$script_file" ]] || continue
        local script_name=$(basename "$script_file" .sh)
        local file_size=$(ls -lh "$script_file" | awk '{print $5}')

        # Check if function exists
        if declare -f "$script_name" >/dev/null 2>&1; then
            echo "[FUNC] $script_name ($file_size)"
        else
            echo "[SCRIPT] $script_name ($file_size)"
        fi
    done

    echo ""
    echo "Run any script name without arguments to see usage help."
}

# Reload scripts function - clears and reloads all scripts
reload_scripts() {
    echo "Reloading scripts from ~/scripts/..."

    # Clear existing aliases for script names
    for script_file in "$HOME/scripts"/*.sh; do
        [[ -f "$script_file" ]] || continue
        local script_name=$(basename "$script_file" .sh)
        unalias "$script_name" 2>/dev/null
        # Also unset the function if it exists
        unset -f "$script_name" 2>/dev/null
    done

    echo "   Cleared existing functions and aliases"

    # Re-source the entire bash config (which sources this autoloader)
    if [[ -f "$HOME/.bashrc" ]]; then
        source "$HOME/.bashrc"
    else
        # Fallback: source this autoloader directly
        source "$HOME/scripts/autoload.bash"
    fi

    echo "   Reloaded complete!"
}

# Make the helper functions available
export -f list_scripts
export -f reload_scripts

# Show success message
echo "Auto-loaded $loaded_count scripts from ~/scripts/ - run 'list_scripts' to see all"

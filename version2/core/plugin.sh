#!/bin/bash
################################################################################
# Multi-Report-OMV
# Plugin System Core Module
# Based on SnapRAID Manager plugin architecture
################################################################################
#
# Table of Contents:
# 1. Configuration
# 2. Plugin Discovery
# 3. Plugin Loading
# 4. Plugin Execution
# 5. Plugin Summaries
# 6. Module Initialization
#
################################################################################

################################################################################
# 1. CONFIGURATION
################################################################################

# Detect script location if not provided
[ -z "$BASE_DIR" ] && BASE_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"

# Plugin directory
PLUGINS_DIR="${BASE_DIR}/plugins"

# Array to store loaded plugins
declare -A LOADED_PLUGINS
declare -a PLUGIN_ORDER

################################################################################
# 2. PLUGIN DISCOVERY
################################################################################

# List all available plugins
list_plugins() {
    local plugins=()
    
    if [ ! -d "$PLUGINS_DIR" ]; then
        return 0
    fi
    
    for plugin_dir in "$PLUGINS_DIR"/*/; do
        if [ -d "$plugin_dir" ]; then
            local plugin_name=$(basename "$plugin_dir")
            
            # Check if manifest exists
            if [ -f "$plugin_dir/manifest.json" ]; then
                plugins+=("$plugin_name")
            fi
        fi
    done
    
    # Output plugins one per line
    printf '%s\n' "${plugins[@]}"
}

# Check if a plugin exists
plugin_exists() {
    local plugin_name="$1"
    local plugin_dir="$PLUGINS_DIR/$plugin_name"
    
    if [ -d "$plugin_dir" ] && [ -f "$plugin_dir/manifest.json" ]; then
        return 0
    else
        return 1
    fi
}

# -------------------------------------------------------
# PLUGIN METADATA
# -------------------------------------------------------

# Get plugin metadata from manifest.json
get_plugin_metadata() {
    local plugin_name="$1"
    local field="$2"
    local default="${3:-}"
    
    local manifest="$PLUGINS_DIR/$plugin_name/manifest.json"
    
    if [ ! -f "$manifest" ]; then
        echo "$default"
        return 1
    fi
    
    # Use jq if available, otherwise fallback to grep/sed
    if command -v jq >/dev/null 2>&1; then
        local value=$(jq -r ".$field // empty" "$manifest" 2>/dev/null)
        if [ -n "$value" ] && [ "$value" != "null" ]; then
            echo "$value"
        else
            echo "$default"
        fi
    else
        # Fallback: simple grep/sed parsing
        local value=$(grep "\"$field\"" "$manifest" | sed -E 's/.*"'$field'"\s*:\s*"?([^",}]+)"?.*/\1/' | tr -d ' ')
        if [ -n "$value" ]; then
            echo "$value"
        else
            echo "$default"
        fi
    fi
}

# Check if plugin is enabled
is_plugin_enabled() {
    local plugin_name="$1"
    local enabled=$(get_plugin_metadata "$plugin_name" "enabled" "true")
    
    if [ "$enabled" = "true" ] || [ "$enabled" = "1" ]; then
        return 0
    else
        return 1
    fi
}

# -------------------------------------------------------
# PLUGIN LOADING
# -------------------------------------------------------

# Initialize the plugin system
init_plugins() {
    log_debug "Initializing plugin system"
    
    # Create plugins directory if it doesn't exist
    if [ ! -d "$PLUGINS_DIR" ]; then
        mkdir -p "$PLUGINS_DIR"
        log_info "Created plugins directory: $PLUGINS_DIR"
    fi
    
    # Discover plugins
    local plugin_count=0
    while IFS= read -r plugin; do
        if [ -n "$plugin" ]; then
            PLUGIN_ORDER+=("$plugin")
            LOADED_PLUGINS["$plugin"]="loaded"
            ((plugin_count++))
        fi
    done < <(list_plugins)
    
    log_info "Discovered $plugin_count plugin(s)"
    
    return 0
}

################################################################################
# 3. PLUGIN LOADING
################################################################################

# Load a specific plugin
load_plugin() {
    local plugin_name="$1"
    
    if ! plugin_exists "$plugin_name"; then
        log_error "Plugin not found: $plugin_name"
        return 1
    fi
    
    local plugin_script="$PLUGINS_DIR/$plugin_name/${plugin_name}.sh"
    
    if [ ! -f "$plugin_script" ]; then
        log_error "Plugin script not found: $plugin_script"
        return 1
    fi
    
    # Source the plugin script
    if ! source "$plugin_script"; then
        log_error "Failed to load plugin: $plugin_name"
        return 1
    fi
    
    log_debug "Loaded plugin: $plugin_name"
    return 0
}

# -------------------------------------------------------
# PLUGIN EXECUTION
# -------------------------------------------------------

# Get plugin summary directory
get_plugin_summary_dir() {
    local plugin_name="$1"
    echo "${TMP_DIR}/plugins/${plugin_name}"
}

# Get plugin summary file path
get_plugin_summary_path() {
    local plugin_name="$1"
    local filename="${2:-summary.txt}"
    echo "$(get_plugin_summary_dir "$plugin_name")/$filename"
}

################################################################################
# 4. PLUGIN EXECUTION
################################################################################

# Execute a plugin
execute_plugin() {
    local plugin_name="$1"
    shift
    local plugin_args=("$@")
    
    log_info "Executing plugin: $plugin_name"
    
    # Check if plugin exists
    if ! plugin_exists "$plugin_name"; then
        log_error "Plugin not found: $plugin_name"
        return 1
    fi
    
    # Check if plugin is enabled
    if ! is_plugin_enabled "$plugin_name"; then
        log_warning "Plugin is disabled: $plugin_name"
        return 2
    fi
    
    # Load the plugin
    if ! load_plugin "$plugin_name"; then
        log_error "Failed to load plugin: $plugin_name"
        return 1
    fi
    
    # Create plugin summary directory
    local summary_dir=$(get_plugin_summary_dir "$plugin_name")
    mkdir -p "$summary_dir"
    
    # Export plugin-specific variables
    export PLUGIN_NAME="$plugin_name"
    export PLUGIN_DIR="$PLUGINS_DIR/$plugin_name"
    export PLUGIN_SUMMARY_DIR="$summary_dir"
    
    # Check if plugin has main function
    if ! type "plugin_${plugin_name//-/_}_main" >/dev/null 2>&1; then
        log_error "Plugin main function not found: plugin_${plugin_name//-/_}_main"
        return 1
    fi
    
    # Execute plugin main function
    local start_time=$(date +%s)
    local exit_code=0
    
    "plugin_${plugin_name//-/_}_main" "${plugin_args[@]}" || exit_code=$?
    
    local end_time=$(date +%s)
    local execution_time=$((end_time - start_time))
    
    if [ $exit_code -eq 0 ]; then
        log_info "Plugin completed successfully: $plugin_name (${execution_time}s)"
    else
        log_error "Plugin failed with exit code $exit_code: $plugin_name (${execution_time}s)"
    fi
    
    return $exit_code
}

# -------------------------------------------------------
# PLUGIN SUMMARY MANAGEMENT
# -------------------------------------------------------

# Read plugin summary
read_plugin_summary() {
    local plugin_name="$1"
    local filename="${2:-summary.txt}"
    
    local summary_file=$(get_plugin_summary_path "$plugin_name" "$filename")
    
    if [ -f "$summary_file" ]; then
        cat "$summary_file"
    else
        # Silently return 1 if summary doesn't exist (not all plugins create summaries)
        return 1
    fi
}

################################################################################
# 5. PLUGIN SUMMARIES
################################################################################

# Write plugin summary
write_plugin_summary() {
    local plugin_name="$1"
    local filename="${2:-summary.txt}"
    local content="$3"
    
    local summary_file=$(get_plugin_summary_path "$plugin_name" "$filename")
    
    echo "$content" > "$summary_file"
    log_debug "Wrote plugin summary: $summary_file"
}

# Combine all plugin summaries
combine_plugin_summaries() {
    local combined=""
    
    for plugin in "${PLUGIN_ORDER[@]}"; do
        local summary=$(read_plugin_summary "$plugin" 2>/dev/null)
        if [ -n "$summary" ]; then
            if [ -n "$combined" ]; then
                combined="${combined}

========================================

${summary}"
            else
                combined="$summary"
            fi
        fi
    done
    
    echo "$combined"
}

# -------------------------------------------------------
# PLUGIN INFORMATION
# -------------------------------------------------------

# Show plugin information
plugin_info() {
    local plugin_name="$1"
    
    if ! plugin_exists "$plugin_name"; then
        echo "Plugin not found: $plugin_name"
        return 1
    fi
    
    echo "Plugin: $plugin_name"
    echo "Description: $(get_plugin_metadata "$plugin_name" "description" "No description")"
    echo "Version: $(get_plugin_metadata "$plugin_name" "version" "Unknown")"
    echo "Enabled: $(get_plugin_metadata "$plugin_name" "enabled" "true")"
    echo "Requires Root: $(get_plugin_metadata "$plugin_name" "requires_root" "false")"
    echo "Location: $PLUGINS_DIR/$plugin_name"
}

################################################################################
# 6. MODULE INITIALIZATION
################################################################################

# Export functions for use in other modules
export -f list_plugins
export -f plugin_exists
export -f get_plugin_metadata
export -f is_plugin_enabled
export -f init_plugins
export -f load_plugin
export -f execute_plugin
export -f get_plugin_summary_dir
export -f get_plugin_summary_path
export -f read_plugin_summary
export -f write_plugin_summary
export -f combine_plugin_summaries
export -f plugin_info

#!/bin/bash
# Multi-Report-OMV - Configuration migration module
#
# This module handles automatic configuration updates when version changes.
# Functions are organized into logical sections for easy navigation and maintenance.
# Version is dynamically read from VERSION file.

# =======================================================
# TABLE OF CONTENTS
# =======================================================
#
# 1. INITIALIZATION
#    - Current configuration version constant
#
# 2. VERSION MANAGEMENT
#    - get_config_version
#    - compare_versions
#    - needs_migration
#
# 3. CONFIGURATION ANALYSIS
#    - get_default_setting_keys
#    - get_active_user_settings
#    - find_new_settings
#    - find_deprecated_settings
#
# 4. MIGRATION OPERATIONS
#    - analyze_migration
#    - migrate_configuration
#
# 5. USER INTERACTION
#    - check_migration_on_startup
#    - show_migration_status
#
# =======================================================

# Detect script location if not provided
[ -z "$BASE_DIR" ] && BASE_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"

# -------------------------------------------------------
# 1. INITIALIZATION
# -------------------------------------------------------

# Current configuration version (increment when config format changes)
readonly CURRENT_CONFIG_VERSION="2.3"

# -------------------------------------------------------
# 2. VERSION MANAGEMENT
# -------------------------------------------------------

# Get configuration version from config file
get_config_version() {
    local config_file="${1:-$USER_CONFIG}"
    
    if [ ! -f "$config_file" ]; then
        echo "0.0"
        return 1
    fi
    
    # Look for CONFIG_VERSION in the file
    local version=$(grep "^CONFIG_VERSION=" "$config_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | xargs)
    
    if [ -z "$version" ]; then
        # No version found - this is a pre-versioning config
        echo "2.0"  # Assume 2.0 for existing configs without version
    else
        echo "$version"
    fi
}

# Compare version numbers (returns 0 if equal, 1 if v1 < v2, 2 if v1 > v2)
compare_versions() {
    local v1="$1"
    local v2="$2"
    
    # Convert to comparable format (remove dots)
    local v1_num=$(echo "$v1" | tr -d '.')
    local v2_num=$(echo "$v2" | tr -d '.')
    
    # Pad with zeros if needed for comparison
    while [ ${#v1_num} -lt ${#v2_num} ]; do v1_num="${v1_num}0"; done
    while [ ${#v2_num} -lt ${#v1_num} ]; do v2_num="${v2_num}0"; done
    
    if [ "$v1_num" -eq "$v2_num" ]; then
        return 0  # Equal
    elif [ "$v1_num" -lt "$v2_num" ]; then
        return 1  # v1 < v2
    else
        return 2  # v1 > v2
    fi
}

# Check if configuration needs migration
needs_migration() {
    local current_version=$(get_config_version)
    
    compare_versions "$current_version" "$CURRENT_CONFIG_VERSION"
    local result=$?
    
    if [ $result -eq 1 ]; then
        # Current version is older than required version
        log_debug "Config version $current_version is older than $CURRENT_CONFIG_VERSION - migration needed"
        return 0
    else
        log_debug "Config version $current_version is up to date"
        return 1
    fi
}

# -------------------------------------------------------
# 3. CONFIGURATION ANALYSIS
# -------------------------------------------------------

# Get list of all setting keys from defaults (CONFIG array)
get_default_setting_keys() {
    echo "${!CONFIG[@]}" | tr ' ' '\n' | sort -u
}

# Get list of active (uncommented) user settings
get_active_user_settings() {
    local user_file="${USER_CONFIG}"
    
    if [ ! -f "$user_file" ]; then
        return 1
    fi
    
    # Get all uncommented settings
    grep -E "^[A-Z_]+=" "$user_file" 2>/dev/null || true
}

# Find new settings that should be added
find_new_settings() {
    local user_file="${USER_CONFIG}"
    
    if [ ! -f "$user_file" ]; then
        return 0
    fi
    
    local user_keys=$(grep -E "^#?[A-Z_]+=" "$user_file" 2>/dev/null | sed 's/^#//' | cut -d'=' -f1 | sort -u)
    local default_keys=$(get_default_setting_keys)
    
    # Find keys in defaults but not in user config
    comm -23 <(echo "$default_keys") <(echo "$user_keys")
}

# Find deprecated settings that should be removed
find_deprecated_settings() {
    local user_file="${USER_CONFIG}"
    
    if [ ! -f "$user_file" ]; then
        return 0
    fi
    
    local user_keys=$(grep -E "^#?[A-Z_]+=" "$user_file" 2>/dev/null | sed 's/^#//' | cut -d'=' -f1 | sort -u)
    local default_keys=$(get_default_setting_keys)
    
    # Find keys in user config but not in defaults
    comm -13 <(echo "$default_keys") <(echo "$user_keys")
}

# -------------------------------------------------------
# 4. MIGRATION OPERATIONS
# -------------------------------------------------------

# Analyze what migration will do
analyze_migration() {
    local user_version=$(get_config_version)
    
    echo "Configuration Migration Analysis"
    echo "================================"
    echo
    echo "Current config version: $user_version"
    echo "Required config version: $CURRENT_CONFIG_VERSION"
    echo
    
    local new_settings=$(find_new_settings)
    local deprecated_settings=$(find_deprecated_settings)
    local active_settings_count=$(get_active_user_settings | wc -l)
    
    if [ -n "$new_settings" ]; then
        echo "New settings to add:"
        while IFS= read -r setting; do
            [ -n "$setting" ] && echo "  + $setting"
        done <<< "$new_settings"
        echo
    else
        echo "No new settings to add."
        echo
    fi
    
    if [ -n "$deprecated_settings" ]; then
        echo "Deprecated settings to remove:"
        while IFS= read -r setting; do
            [ -n "$setting" ] && echo "  - $setting"
        done <<< "$deprecated_settings"
        echo
    else
        echo "No deprecated settings to remove."
        echo
    fi
    
    echo "Active user settings: $active_settings_count (will be preserved)"
    echo
}

# Perform configuration migration
migrate_configuration() {
    local user_version=$(get_config_version)
    
    log_info "Starting configuration migration from v$user_version to v$CURRENT_CONFIG_VERSION"
    
    # Create backup before migration
    local backup_file="${USER_CONFIG}.backup-$(date +%Y%m%d-%H%M%S)"
    log_info "Creating backup: $backup_file"
    cp "$USER_CONFIG" "$backup_file" 2>/dev/null || {
        log_error "Failed to create backup - aborting migration"
        return 1
    }
    
    # Get active user settings before regeneration
    local active_settings=$(get_active_user_settings)
    log_debug "Preserving user settings from old config"
    
    # Create associative array of user's values
    declare -A user_values
    while IFS='=' read -r key value; do
        if [[ "$key" =~ ^[A-Z_]+$ ]]; then
            # Remove quotes from value
            value="${value%\"}"
            value="${value#\"}"
            user_values["$key"]="$value"
            log_debug "Preserved: $key"
        fi
    done < <(echo "$active_settings")
    
    # Generate fresh config template
    log_info "Generating new config template with current options"
    
    create_user_config
    
    # Build list of valid keys from the new template
    declare -A valid_keys
    while IFS= read -r line; do
        if [[ "$line" =~ ^#?([A-Z_]+)= ]]; then
            valid_keys["${BASH_REMATCH[1]}"]=1
        fi
    done < "$USER_CONFIG"
    
    # Track deprecated settings that won't be migrated
    local skipped_settings=()
    
    # Check for user settings that don't exist in new template
    for key in "${!user_values[@]}"; do
        if [ -z "${valid_keys[$key]+isset}" ] && [ "$key" != "CONFIG_VERSION" ]; then
            log_warning "Skipping deprecated setting: $key (no longer supported)"
            skipped_settings+=("$key=\"${user_values[$key]}\"")
        fi
    done
    
    # Apply user's values back to the new config
    log_info "Applying your custom settings to new template"
    
    local temp_config=$(mktemp)
    
    while IFS= read -r line; do
        # Check if this is a setting line (commented or not)
        if [[ "$line" =~ ^#?([A-Z_]+)= ]]; then
            local key="${BASH_REMATCH[1]}"
            
            # Always use current version for CONFIG_VERSION
            if [ "$key" = "CONFIG_VERSION" ]; then
                echo "CONFIG_VERSION=\"$CURRENT_CONFIG_VERSION\"" >> "$temp_config"
                continue
            fi
            
            # Check if user had this setting active AND it's still valid
            if [ -n "${user_values[$key]+isset}" ]; then
                # User has this setting - use their value (uncommented)
                echo "${key}=\"${user_values[$key]}\"" >> "$temp_config"
                log_debug "Applied user value: $key"
            else
                # User doesn't have it - keep as default (commented)
                echo "$line" >> "$temp_config"
            fi
        else
            # Comment lines, section headers, empty lines - copy as-is
            echo "$line" >> "$temp_config"
        fi
    done < "$USER_CONFIG"
    
    # Replace user config with migrated version
    mv "$temp_config" "$USER_CONFIG"
    
    log_info "✓ Configuration migrated successfully to v$CURRENT_CONFIG_VERSION"
    log_info "✓ Your custom values preserved"
    log_info "✓ New options added (commented out)"
    
    if [ ${#skipped_settings[@]} -gt 0 ]; then
        log_warning "✓ Removed ${#skipped_settings[@]} deprecated setting(s):"
        for setting in "${skipped_settings[@]}"; do
            log_warning "  - $setting"
        done
    else
        log_info "✓ No deprecated settings to remove"
    fi
    
    log_info "✓ Backup saved: $backup_file"
    
    return 0
}

# -------------------------------------------------------
# 5. USER INTERACTION
# -------------------------------------------------------

# Check and handle migration on startup
check_migration_on_startup() {
    if ! needs_migration; then
        log_debug "Configuration is up to date (v$(get_config_version))"
        return 0
    fi
    
    local user_version=$(get_config_version)
    log_info "Configuration update available: v$user_version → v$CURRENT_CONFIG_VERSION"
    
    # Automatically migrate (with backup)
    log_info "Auto-migrating configuration..."
    
    if migrate_configuration; then
        log_info "Configuration updated successfully"
        return 0
    else
        log_error "Configuration migration failed"
        log_warning "Continuing with old configuration - some features may not work"
        return 1
    fi
}

# Show migration status
show_migration_status() {
    local current_version=$(get_config_version)
    
    echo "Configuration Version Status"
    echo "============================"
    echo
    echo "Current configuration version: $current_version"
    echo "Required configuration version: $CURRENT_CONFIG_VERSION"
    echo
    
    compare_versions "$current_version" "$CURRENT_CONFIG_VERSION"
    local result=$?
    
    case $result in
        0)
            echo "Status: ✓ Up to date"
            ;;
        1)
            echo "Status: ⚠ Migration recommended"
            echo
            echo "Your configuration will be automatically updated on next run."
            ;;
        2)
            echo "Status: ⚠ Configuration is newer than script"
            echo
            echo "Your config version is newer than expected."
            echo "Did you downgrade the script?"
            ;;
    esac
    echo
}

# Module initialization
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    if type log_debug >/dev/null 2>&1; then
        log_debug "Config migration module loaded (v$CURRENT_CONFIG_VERSION)"
    fi
fi

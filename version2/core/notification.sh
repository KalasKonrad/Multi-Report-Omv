#!/bin/bash
################################################################################
# Multi-Report-OMV
# Core Notification Module
# Pluggable notification delivery framework
################################################################################
#
# Table of Contents:
# 1. Configuration
# 2. Notification Registry
# 3. Notification Management
# 4. Module Initialization
#
################################################################################

################################################################################
# 1. CONFIGURATION
################################################################################

# Detect script location
[ -z "$BASE_DIR" ] && BASE_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"

# Notification delivery methods registry
declare -A NOTIFICATION_METHODS

################################################################################
# 2. NOTIFICATION REGISTRY
################################################################################

# Register a notification delivery method
# Usage: register_notification_method <name> <function> <enabled_config_key>
register_notification_method() {
    local name="$1"
    local function="$2"
    local config_key="$3"
    
    if [ -z "$name" ] || [ -z "$function" ]; then
        log_error "register_notification_method: name and function required"
        return 1
    fi
    
    NOTIFICATION_METHODS["$name"]="${function}:${config_key}"
    log_debug "Registered notification method: $name (function: $function, config: $config_key)"
}

# Check if notification method is enabled
is_notification_enabled() {
    local name="$1"
    
    if [ -z "${NOTIFICATION_METHODS[$name]}" ]; then
        return 1
    fi
    
    local config_key=$(echo "${NOTIFICATION_METHODS[$name]}" | cut -d: -f2)
    
    if [ -z "$config_key" ]; then
        # No config key, assume enabled
        return 0
    fi
    
    local enabled=$(get_config "$config_key" "false")
    [ "$enabled" = "true" ] && return 0
    return 1
}

# Get notification function for a method
get_notification_function() {
    local name="$1"
    
    if [ -z "${NOTIFICATION_METHODS[$name]}" ]; then
        return 1
    fi
    
    echo "${NOTIFICATION_METHODS[$name]}" | cut -d: -f1
}

################################################################################
# 3. NOTIFICATION MANAGEMENT
################################################################################

# Send notification via specified method
# Usage: send_notification <method> <subject> <message> [options...]
send_notification() {
    local method="$1"
    local subject="$2"
    local message="$3"
    shift 3
    
    if ! is_notification_enabled "$method"; then
        log_debug "Notification method '$method' is disabled"
        return 0
    fi
    
    local func=$(get_notification_function "$method")
    if [ -z "$func" ]; then
        log_error "Unknown notification method: $method"
        return 1
    fi
    
    if ! type "$func" &>/dev/null; then
        log_error "Notification function not found: $func"
        return 1
    fi
    
    log_info "Sending notification via $method"
    "$func" "$subject" "$message" "$@"
    local result=$?
    
    if [ $result -eq 0 ]; then
        log_info "Notification sent successfully via $method"
    else
        log_error "Failed to send notification via $method (exit code: $result)"
    fi
    
    return $result
}

# Send notification via all enabled methods
# Usage: send_notification_all <subject> <message> [options...]
send_notification_all() {
    local subject="$1"
    local message="$2"
    shift 2
    
    local sent_count=0
    local fail_count=0
    
    for method in "${!NOTIFICATION_METHODS[@]}"; do
        if is_notification_enabled "$method"; then
            if send_notification "$method" "$subject" "$message" "$@"; then
                ((sent_count++))
            else
                ((fail_count++))
            fi
        fi
    done
    
    if [ $sent_count -eq 0 ] && [ $fail_count -eq 0 ]; then
        log_debug "No notification methods enabled"
        return 0
    fi
    
    log_info "Sent $sent_count notification(s), $fail_count failed"
    
    [ $fail_count -gt 0 ] && return 1
    return 0
}

# Send report notification (convenience function)
# Automatically determines subject and formats message
send_report_notification() {
    local report_name="$1"
    local report_file="$2"
    local has_errors="${3:-false}"
    
    if [ ! -f "$report_file" ]; then
        log_error "Report file not found: $report_file"
        return 1
    fi
    
    # Determine subject
    local subject="${CONFIG[EMAIL_SUBJECT_PREFIX]:-[Multi-Report-OMV]} $report_name - $(date '+%Y-%m-%d')"
    
    if [ "$has_errors" = "true" ]; then
        subject="[ERROR] $subject"
    fi
    
    # Check notification level
    local level="${CONFIG[EMAIL_LEVEL]:-always}"
    
    case "$level" in
        error)
            if [ "$has_errors" != "true" ]; then
                log_debug "Notification level is 'error', but no errors detected - skipping"
                return 0
            fi
            ;;
        warning)
            # For now, treat warning same as error (future: add warning detection)
            if [ "$has_errors" != "true" ]; then
                log_debug "Notification level is 'warning', but no errors/warnings - skipping"
                return 0
            fi
            ;;
        always)
            # Always send
            ;;
        *)
            log_error "Invalid notification level: $level"
            return 1
            ;;
    esac
    
    # Read report content
    local message=$(cat "$report_file")
    
    # Send via all enabled methods
    send_notification_all "$subject" "$message" "$report_file"
}

# List registered notification methods
list_notification_methods() {
    echo "Registered notification methods:"
    for method in "${!NOTIFICATION_METHODS[@]}"; do
        local status="disabled"
        is_notification_enabled "$method" && status="enabled"
        local func=$(get_notification_function "$method")
        echo "  - $method: $status (function: $func)"
    done
}

################################################################################
# 4. MODULE INITIALIZATION
################################################################################

# Load notification delivery modules
load_notification_modules() {
    local modules_dir="${BASE_DIR}/core"
    
    # Load email module if available
    if [ -f "$modules_dir/email.sh" ]; then
        source "$modules_dir/email.sh"
        log_debug "Loaded email notification module"
    fi
    
    # Future: Load other notification modules
    # - discord.sh
    # - telegram.sh
    # - slack.sh
    # - teams.sh
    # - webhook.sh
}

# Initialize notification system
init_notifications() {
    log_debug "Initializing notification system"
    
    # Load delivery modules
    load_notification_modules
    
    log_debug "Notification system initialized with ${#NOTIFICATION_METHODS[@]} method(s)"
}

# Initialize on source
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    init_notifications
fi

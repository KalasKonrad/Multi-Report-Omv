#!/bin/bash
# Multi-Report-OMV - Configuration backup & restore module
#
# This module provides automatic and manual backup/restore functionality for configurations.
# Functions are organized into logical sections for easy navigation and maintenance.
# Version is dynamically read from VERSION file.

# =======================================================
# TABLE OF CONTENTS
# =======================================================
#
# 1. CONFIGURATION
#    - get_backup_dir
#    - get_backup_retention
#    - generate_backup_filename
#
# 2. BACKUP OPERATIONS
#    - backup_config
#    - rotate_backups
#
# 3. BACKUP QUERIES
#    - list_config_backups
#    - get_backup_by_number
#    - validate_backup
#
# 4. RESTORE OPERATIONS
#    - restore_config
#
# 5. INFORMATION & MAINTENANCE
#    - show_backup_info
#    - clean_all_backups
#
# =======================================================

# Detect script location if not provided
[ -z "$BASE_DIR" ] && BASE_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"

# -------------------------------------------------------
# 1. CONFIGURATION
# -------------------------------------------------------

# Get backup directory based on installation type
get_backup_dir() {
    local backup_dir="$CONFIG_DIR/backups"
    echo "$backup_dir"
}

# Get backup retention count from config (default: 5)
get_backup_retention() {
    local retention=$(get_config "CONFIG_BACKUP_RETENTION" "5")
    echo "$retention"
}

# Create timestamped backup filename
generate_backup_filename() {
    local timestamp=$(date +%Y%m%d-%H%M%S)
    echo "multi-report-omv.conf.backup.$timestamp"
}

# -------------------------------------------------------
# 2. BACKUP OPERATIONS
# -------------------------------------------------------

# Create a configuration backup
# Usage: backup_config [reason]
# Returns: 0 on success, 1 on failure
backup_config() {
    local reason="${1:-manual backup}"
    local config_file="$USER_CONFIG"
    local backup_dir=$(get_backup_dir)
    local backup_file="$backup_dir/$(generate_backup_filename)"
    
    # Check if config file exists
    if [ ! -f "$config_file" ]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi
    
    # Create backup directory
    mkdir -p "$backup_dir" 2>/dev/null
    if [ $? -ne 0 ]; then
        log_error "Failed to create backup directory: $backup_dir"
        return 1
    fi
    
    log_info "Creating configuration backup: $reason"
    cp "$config_file" "$backup_file" 2>/dev/null
    if [ $? -ne 0 ]; then
        log_error "Failed to create backup file: $backup_file"
        return 1
    fi
    
    log_info "Configuration backed up to: $backup_file"
    
    # Rotate old backups
    rotate_backups
    
    return 0
}

# Rotate backups based on retention policy
rotate_backups() {
    local backup_dir=$(get_backup_dir)
    local retention=$(get_backup_retention)
    
    local backup_count=$(find "$backup_dir" -name "multi-report-omv.conf.backup.*" -type f 2>/dev/null | wc -l)
    
    if [ "$backup_count" -le "$retention" ]; then
        return 0
    fi
    
    log_debug "Rotating backups (keeping last $retention of $backup_count)"
    
    local backups_to_delete=$((backup_count - retention))
    find "$backup_dir" -name "multi-report-omv.conf.backup.*" -type f -printf '%T+ %p\n' 2>/dev/null | \
        sort | \
        head -n "$backups_to_delete" | \
        cut -d' ' -f2- | \
        while IFS= read -r old_backup; do
            log_debug "Removing old backup: $(basename "$old_backup")"
            rm -f "$old_backup"
        done
    
    return 0
}

# -------------------------------------------------------
# 3. BACKUP QUERIES
# -------------------------------------------------------

# List available configuration backups
list_config_backups() {
    local backup_dir=$(get_backup_dir)
    
    if [ ! -d "$backup_dir" ]; then
        echo "No backups directory found."
        return 1
    fi
    
    local backups=$(find "$backup_dir" -name "multi-report-omv.conf.backup.*" -type f -printf '%T+ %p\n' 2>/dev/null | \
        sort -r | \
        cut -d' ' -f2-)
    
    if [ -z "$backups" ]; then
        echo "No configuration backups found."
        return 1
    fi
    
    echo "Available configuration backups:"
    echo "================================"
    echo
    
    local count=1
    while IFS= read -r backup_file; do
        local filename=$(basename "$backup_file")
        local timestamp=$(echo "$filename" | sed 's/multi-report-omv.conf.backup.\(.*\)/\1/')
        local date_str=$(echo "$timestamp" | sed 's/\([0-9]\{8\}\)-\([0-9]\{6\}\)/\1 \2/')
        local formatted_date=$(date -d "${date_str:0:8} ${date_str:9:2}:${date_str:11:2}:${date_str:13:2}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$timestamp")
        local size=$(stat -c%s "$backup_file" 2>/dev/null || echo "unknown")
        
        printf "%2d) %s (%s bytes)\n" "$count" "$formatted_date" "$size"
        printf "    File: %s\n" "$filename"
        echo
        
        count=$((count + 1))
    done <<< "$backups"
    
    return 0
}

# Get backup file by number from list
get_backup_by_number() {
    local number="$1"
    local backup_dir=$(get_backup_dir)
    
    if [ ! -d "$backup_dir" ]; then
        echo ""
        return 1
    fi
    
    local backup=$(find "$backup_dir" -name "multi-report-omv.conf.backup.*" -type f -printf '%T+ %p\n' 2>/dev/null | \
        sort -r | \
        sed -n "${number}p" | \
        cut -d' ' -f2-)
    
    echo "$backup"
    [ -n "$backup" ]
}

# Validate backup file integrity
validate_backup() {
    local backup_file="$1"
    
    if [ ! -f "$backup_file" ]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi
    
    if [ ! -r "$backup_file" ]; then
        log_error "Backup file not readable: $backup_file"
        return 1
    fi
    
    if [ ! -s "$backup_file" ]; then
        log_error "Backup file is empty: $backup_file"
        return 1
    fi
    
    # Basic validation - check if it looks like a config file
    if ! grep -q "^#.*Multi-Report-OMV" "$backup_file" 2>/dev/null; then
        log_warning "Backup file may not be a valid Multi-Report-OMV configuration"
        log_warning "File: $backup_file"
    fi
    
    return 0
}

# -------------------------------------------------------
# 4. RESTORE OPERATIONS
# -------------------------------------------------------

# Restore configuration from backup
# Usage: restore_config <backup_file> [--no-backup]
# Returns: 0 on success, 1 on failure
restore_config() {
    local backup_file="$1"
    local skip_backup="${2:-}"
    local config_file="$USER_CONFIG"
    
    # Validate backup file
    if ! validate_backup "$backup_file"; then
        return 1
    fi
    
    # Backup current config before restoring (unless skipped)
    if [ "$skip_backup" != "--no-backup" ] && [ -f "$config_file" ]; then
        log_info "Backing up current configuration before restore..."
        backup_config "pre-restore backup"
    fi
    
    log_info "Restoring configuration from: $(basename "$backup_file")"
    cp "$backup_file" "$config_file" 2>/dev/null
    if [ $? -ne 0 ]; then
        log_error "Failed to restore configuration from backup"
        return 1
    fi
    
    log_info "Configuration restored successfully"
    log_info "Reloading configuration..."
    
    # Reload configuration if function exists
    if type load_config >/dev/null 2>&1; then
        load_config
    fi
    
    return 0
}

# -------------------------------------------------------
# 5. INFORMATION & MAINTENANCE
# -------------------------------------------------------

# Show detailed information about a backup file
show_backup_info() {
    local backup_file="$1"
    
    if [ ! -f "$backup_file" ]; then
        echo "Backup file not found: $backup_file"
        return 1
    fi
    
    echo "Backup File Information"
    echo "======================="
    echo
    echo "File: $(basename "$backup_file")"
    echo "Path: $backup_file"
    echo "Size: $(stat -c%s "$backup_file" 2>/dev/null || echo "unknown") bytes"
    echo "Modified: $(stat -c%y "$backup_file" 2>/dev/null | cut -d. -f1)"
    echo
    echo "Active Settings (non-commented):"
    echo "--------------------------------"
    grep -v "^#" "$backup_file" | grep "=" | head -n 20
    local total_settings=$(grep -v "^#" "$backup_file" | grep "=" | wc -l)
    if [ "$total_settings" -gt 20 ]; then
        echo "... and $((total_settings - 20)) more settings"
    fi
    echo
    
    return 0
}

# Clean all backups with confirmation
clean_all_backups() {
    local force="${1:-}"
    local backup_dir=$(get_backup_dir)
    
    if [ ! -d "$backup_dir" ]; then
        echo "No backups directory found."
        return 0
    fi
    
    local backup_count=$(find "$backup_dir" -name "multi-report-omv.conf.backup.*" -type f 2>/dev/null | wc -l)
    
    if [ "$backup_count" -eq 0 ]; then
        echo "No backups to clean."
        return 0
    fi
    
    if [ "$force" != "--force" ]; then
        echo "Found $backup_count backup(s)."
        read -p "Delete all backups? This cannot be undone. [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy] ]]; then
            echo "Clean cancelled."
            return 1
        fi
    fi
    
    find "$backup_dir" -name "multi-report-omv.conf.backup.*" -type f -delete
    echo "All backups deleted."
    
    return 0
}

# Module initialization
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    if type log_debug >/dev/null 2>&1; then
        log_debug "Config backup module loaded"
    fi
fi

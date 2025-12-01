#!/usr/bin/env bash
#
# Multi-Report-OMV
# SMR Check Plugin - Detect CMR vs SMR drives
#

PLUGIN_NAME="smr_check"
VERSION="1.0.0"

# Core modules (logger, utils, config) are sourced by main script
# Plugins are always loaded via execute_plugin() which ensures core modules are available

################################################################################
# CONFIGURATION
################################################################################

# Get cache file location from config
get_cache_file() {
    local cache_file="${CONFIG[SMR_CACHE_FILE]:-${BASE_DIR}/data/smr_check/drive_types.cache}"
    mkdir -p "$(dirname "$cache_file")"
    echo "$cache_file"
}

################################################################################
# CACHE MANAGEMENT
################################################################################

# Generate a hash of current drive configuration (serials + models)
get_drive_config_hash() {
    local drives=$(get_smart_drives)
    local config_string=""
    
    for drive in $drives; do
        local serial=$(get_drive_serial "$drive")
        local model=$(get_drive_model "$drive")
        config_string="${config_string}${drive}:${serial}:${model}|"
    done
    
    echo "$config_string" | md5sum | awk '{print $1}'
}

# Check if cache is valid (drive configuration hasn't changed)
is_cache_valid() {
    local cache_file=$(get_cache_file)
    
    if [ ! -f "$cache_file" ]; then
        return 1
    fi
    
    # Get stored hash from first line of cache
    local stored_hash=$(head -1 "$cache_file" 2>/dev/null | cut -d'|' -f1)
    local current_hash=$(get_drive_config_hash)
    
    if [ "$stored_hash" = "$current_hash" ]; then
        return 0
    else
        return 1
    fi
}

# Save SMR check results to cache
save_to_cache() {
    local cache_file=$(get_cache_file)
    local current_hash=$(get_drive_config_hash)
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    # Write header with hash and timestamp
    echo "${current_hash}|${timestamp}" > "$cache_file"
    echo "# Drive|Serial|Model|Type|Detection_Method" >> "$cache_file"
    
    # Write drive data
    local drives=$(get_smart_drives)
    for drive in $drives; do
        local serial=$(get_drive_serial "$drive")
        local model=$(get_drive_model "$drive")
        local type=$(check_drive_recording_type "$drive")
        local method=$(get_detection_method "$drive")
        
        echo "${drive}|${serial}|${model}|${type}|${method}" >> "$cache_file"
    done
    
    log_info "SMR check results cached to: $cache_file"
}

# Get detection method for logging purposes
get_detection_method() {
    local drive="$1"
    
    # Check kernel attribute
    if [ -f "/sys/block/$drive/device/zoned" ]; then
        local zoned=$(cat /sys/block/$drive/device/zoned 2>/dev/null)
        if [ "$zoned" = "host-managed" ] || [ "$zoned" = "host-aware" ]; then
            echo "kernel"
            return
        fi
    fi
    
    # Check if SMR script would detect it
    local smr_script="${BASE_DIR}/../smr-check-omv.sh"
    if [ -f "$smr_script" ]; then
        local serial=$(get_drive_serial "$drive")
        if [ -n "$serial" ]; then
            local smr_output=$(bash "$smr_script" 2>/dev/null)
            if echo "$smr_output" | grep -q "Known SMR drive(s) detected"; then
                local smr_table=$(echo "$smr_output" | sed -n '/Known SMR drive(s) detected/,$p' | tail -n +3)
                if echo "$smr_table" | grep -q "$serial"; then
                    echo "database"
                    return
                fi
            fi
        fi
    fi
    
    # Check pattern match
    local model=$(get_drive_model "$drive")
    if [ -n "$model" ]; then
        case "$model" in
            *"ST8000AS"*|*"ST6000AS"*|*"ST5000AS"*|*"ST4000AS"*|*"ST3000AS"*|*"ST2000AS"*|\
            *"WD60EZAZ"*|*"WD40EZAZ"*|*"WD30EZAZ"*|*"WD20EZAZ"*|\
            *"ST2000DM008"*|*"ST2000DM005"*|*"ST3000DM007"*|*"ST4000DM004"*|*"ST5000DM000"*|*"ST6000DM003"*|\
            *"DT01ACA"*|*"MG08ACA"*)
                echo "pattern"
                return
                ;;
        esac
    fi
    
    echo "default"
}

# Read cached results
read_cache() {
    local cache_file=$(get_cache_file)
    
    if [ ! -f "$cache_file" ]; then
        return 1
    fi
    
    # Skip first two lines (hash header and column header)
    tail -n +3 "$cache_file"
}

################################################################################
# SMR DETECTION & REPORTING
################################################################################

# Scan all drives and detect SMR
scan_drives() {
    local force_rescan="${1:-false}"
    
    log_info "Starting SMR/CMR drive detection scan"
    
    # Check cache validity unless forced
    if [ "$force_rescan" != "true" ] && is_cache_valid; then
        log_info "Using cached SMR detection results (drive configuration unchanged)"
        display_cached_results
        return 0
    fi
    
    log_info "Scanning drives for SMR detection..."
    
    local drives=$(get_smart_drives)
    local smr_count=0
    local cmr_count=0
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║                          SMR/CMR Drive Detection                           ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    printf "%-8s %-15s %-25s %-10s %-12s\n" "Drive" "Serial" "Model" "Type" "Method"
    echo "--------------------------------------------------------------------------------"
    
    for drive in $drives; do
        local serial=$(get_drive_serial "$drive")
        local model=$(get_drive_model "$drive")
        local type=$(check_drive_recording_type "$drive")
        local method=$(get_detection_method "$drive")
        
        # Truncate model if too long
        local model_display="$model"
        if [ ${#model} -gt 25 ]; then
            model_display="${model:0:22}..."
        fi
        
        printf "%-8s %-15s %-25s %-10s %-12s\n" "$drive" "$serial" "$model_display" "$type" "$method"
        
        if [[ "$type" == SMR* ]]; then
            ((smr_count++))
        else
            ((cmr_count++))
        fi
    done
    
    echo "--------------------------------------------------------------------------------"
    echo "Summary: $cmr_count CMR drive(s), $smr_count SMR drive(s)"
    echo ""
    
    # Show warnings if SMR drives detected
    if [ $smr_count -gt 0 ] && [ "${CONFIG[SMR_WARN_ON_DETECTION]}" = "true" ]; then
        echo "⚠ WARNING: SMR drives detected!"
        echo ""
        echo "  SMR (Shingled Magnetic Recording) drives may have performance issues with:"
        echo "  - RAID arrays (especially RAID5/6)"
        echo "  - ZFS pools"
        echo "  - Frequent random writes"
        echo "  - Drive rebuilds"
        echo ""
        echo "  Consider using CMR drives for critical NAS/RAID applications."
        echo ""
    fi
    
    # Save results to cache
    save_to_cache
    
    log_info "SMR detection scan completed: $cmr_count CMR, $smr_count SMR"
}

# Display cached results
display_cached_results() {
    local cache_file=$(get_cache_file)
    local timestamp=$(head -1 "$cache_file" | cut -d'|' -f2)
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║                    SMR/CMR Drive Detection (Cached)                        ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Last scanned: $timestamp"
    echo ""
    printf "%-8s %-15s %-25s %-10s %-12s\n" "Drive" "Serial" "Model" "Type" "Method"
    echo "--------------------------------------------------------------------------------"
    
    local smr_count=0
    local cmr_count=0
    
    while IFS='|' read -r drive serial model type method; do
        # Truncate model if too long
        local model_display="$model"
        if [ ${#model} -gt 25 ]; then
            model_display="${model:0:22}..."
        fi
        
        printf "%-8s %-15s %-25s %-10s %-12s\n" "$drive" "$serial" "$model_display" "$type" "$method"
        
        if [[ "$type" == SMR* ]]; then
            ((smr_count++))
        else
            ((cmr_count++))
        fi
    done < <(read_cache)
    
    echo "--------------------------------------------------------------------------------"
    echo "Summary: $cmr_count CMR drive(s), $smr_count SMR drive(s)"
    echo ""
    
    # Show warnings if SMR drives detected
    if [ $smr_count -gt 0 ] && [ "${CONFIG[SMR_WARN_ON_DETECTION]}" = "true" ]; then
        echo "⚠ WARNING: SMR drives detected!"
        echo ""
        echo "  SMR (Shingled Magnetic Recording) drives may have performance issues with:"
        echo "  - RAID arrays (especially RAID5/6)"
        echo "  - ZFS pools"
        echo "  - Frequent random writes"
        echo "  - Drive rebuilds"
        echo ""
        echo "  Consider using CMR drives for critical NAS/RAID applications."
        echo ""
    fi
    
    echo "Run with --force to rescan drives"
    echo ""
}

################################################################################
# PLUGIN COMMANDS
################################################################################

# Main plugin entry point
plugin_smr_check_main() {
    local force_rescan="${1:-false}"
    
    if [ "${CONFIG[SMR_CHECK_ENABLED]}" != "true" ]; then
        log_info "SMR check plugin is disabled"
        return 0
    fi
    
    scan_drives "$force_rescan"
}

# Command: smr-check
cmd_smr_check() {
    local force=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force|-f)
                force=true
                shift
                ;;
            --help|-h)
                echo "Usage: multi-report-omv smr-check [OPTIONS]"
                echo ""
                echo "Detect SMR (Shingled Magnetic Recording) vs CMR drives"
                echo ""
                echo "Options:"
                echo "  --force, -f    Force rescan (ignore cache)"
                echo "  --help, -h     Show this help message"
                echo ""
                echo "Drive Types:"
                echo "  CMR         Conventional Magnetic Recording (standard HDD)"
                echo "  SMR         Shingled Magnetic Recording (detected via database/pattern)"
                echo "  SMR-HM      Host-Managed SMR (requires OS support)"
                echo "  SMR-HA      Host-Aware SMR (can work like CMR)"
                echo ""
                return 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                return 1
                ;;
        esac
    done
    
    plugin_smr_check_main "$force"
}

################################################################################
# MODULE INITIALIZATION
################################################################################

# If script is sourced by plugin loader, export the command
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    log_debug "SMR check plugin loaded"
fi

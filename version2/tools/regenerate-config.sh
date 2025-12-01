#!/bin/bash
################################################################################
# Configuration Regeneration Tool
# Recreates user configuration file with all current options
################################################################################

# Get script directory
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Source core modules
source "${BASE_DIR}/core/logger.sh"
source "${BASE_DIR}/core/config.sh"

echo "=================================="
echo "Configuration Regeneration Tool"
echo "=================================="
echo ""

# Initialize logging to console only
LOG_LEVEL="info"
init_logging

# Check if user config exists
USER_CONFIG="${CONFIG_DIR:-$BASE_DIR/config}/multi-report-omv.conf"

if [ -f "$USER_CONFIG" ]; then
    echo "Current config file found: $USER_CONFIG"
    echo ""
    echo "Options:"
    echo "1) Backup current config and create new one (recommended)"
    echo "2) Add missing options to current config"
    echo "3) Cancel"
    echo ""
    read -p "Choose option [1-3]: " choice
    
    case "$choice" in
        1)
            # Create backup
            backup_file="${USER_CONFIG}.backup-$(date +%Y%m%d-%H%M%S)"
            cp "$USER_CONFIG" "$backup_file"
            echo "Backup created: $backup_file"
            
            # Initialize config to get all defaults
            init_default_config
            
            # Create new user config
            create_user_config
            
            echo ""
            echo "✓ New configuration file created"
            echo "✓ Old config backed up to: $backup_file"
            echo ""
            echo "Next steps:"
            echo "1. Review the new config: $USER_CONFIG"
            echo "2. Transfer your custom settings from the backup"
            echo "3. Uncomment and modify options as needed"
            ;;
        2)
            # Initialize config and load existing
            init_default_config
            load_config_file "$USER_CONFIG"
            
            # Check for missing options
            check_and_update_user_config
            
            echo ""
            echo "✓ Configuration updated with any missing options"
            echo "✓ Backup saved to: ${USER_CONFIG}.autobackup"
            ;;
        3)
            echo "Cancelled"
            exit 0
            ;;
        *)
            echo "Invalid choice"
            exit 1
            ;;
    esac
else
    echo "No existing config file found"
    echo "Creating new configuration file..."
    
    # Initialize config
    init_default_config
    
    # Create new user config
    create_user_config
    
    echo ""
    echo "✓ Configuration file created: $USER_CONFIG"
    echo ""
    echo "Next steps:"
    echo "1. Edit the config file to customize your settings"
    echo "2. Uncomment the options you want to change"
    echo "3. Save and run the main script"
fi

echo ""
echo "Configuration location: $USER_CONFIG"
echo ""

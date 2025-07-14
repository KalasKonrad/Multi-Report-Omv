#!/bin/bash
# shellcheck disable=SC1075,SC2027,SC2034,SC2128,SC2002,SC2004,SC2086,SC2162
LANG="en_US.UTF-8"

##### Multi-Report OMV Fork - Version 1.2-beta
##### Adapted from Multi-Report v3.18 for OpenMediaVault
##### SnapRAID management handled by separate script
##### Added SMR drive detection functionality

# THIS IS A FORK OF MULTI-REPORT ADAPTED FOR OPENMEDIAVAULT
# Original Multi-Report by joeschmuck, modified for OMV environment
# SnapRAID status/sync removed - handled by separate SnapRAID manager

###### Get Config File Name and Location
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
Config_File_Name="$SCRIPT_DIR/multi_report_omv_config.txt"
Statistical_Data_File="$SCRIPT_DIR/statisticalsmartdata_omv.csv"

###### Load Configuration File
load_config() {
    # Set default values first
    Drive_Temp_Warn=45
    Drive_Temp_Critical=50
    SSD_Temp_Warn=50
    SSD_Temp_Critical=60
    NVMe_Temp_Warn=60
    NVMe_Temp_Critical=70
    
    # Set default warning deltas (only used with SCT data)
    Drive_Temp_Warning_Delta=10
    SSD_Temp_Warning_Delta=10
    NVMe_Temp_Warning_Delta=15
    Use_SCT_Temperature_Data=true
    
    # SMR Drive Detection settings
    SMR_Enable=true
    SMR_Update=true
    SMR_Ignore_Alarm=false
    
    # Statistical Data Recording settings
    SDF_DataRecordEnable=true
    SDF_DataPurgeDays=730
    
    # CSV File Ownership settings
    CSV_File_Owner=""      # User who should own the CSV file (default: root)
    CSV_File_Group=""      # Group who should own the CSV file (default: root)
    CSV_File_Permissions="644"  # File permissions for CSV file (default: 644)
    
    # Email notification settings
    Email_Enable=true
    Email_To=""
    Email_From=""
    Email_Subject_Prefix="[Multi-Report]"
    Email_Include_Hostname=true
    Email_Use_HTML=false
    Email_Attach_Logs=false
    Email_Attach_CSV=false
    Email_Level="issues"
    
    # SMART Testing settings (for drive_selftest_omv.sh integration)
    Short_Test_Mode=3
    Short_SMART_Testing_Order="DriveID"
    Short_Drives_to_Test_Per_Day=2
    Short_Drives_Test_Period="Week"
    Short_Drives_Tested_Days_of_the_Week="1,2,3,4,5"
    Short_Time_Delay_Between_Drives=60
    Long_Test_Mode=3
    Long_SMART_Testing_Order="Serial"
    Long_Drives_to_Test_Per_Day=1
    Long_Drives_Test_Period="Month"
    Long_Drives_Tested_Days_of_the_Week="6,7"
    Long_Time_Delay_Between_Drives=120
    Test_ONLY_NVMe_Drives="false"
    Ignore_Drives_List=""
    
    # Load user configuration if available
    if [ -f "$Config_File_Name" ]; then
        echo "Loading configuration from: $Config_File_Name"
        # Source the config file safely
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ $key =~ ^[[:space:]]*# ]] && continue
            [[ -z $key ]] && continue
            
            # Remove any quotes, comments, and whitespace
            key=$(echo "$key" | tr -d '[:space:]')
            
            # Handle boolean values for Use_SCT_Temperature_Data, SMR settings, Email settings, and SMART testing
            if [ "$key" = "Use_SCT_Temperature_Data" ] || [ "$key" = "SMR_Enable" ] || [ "$key" = "SMR_Update" ] || [ "$key" = "SMR_Ignore_Alarm" ] || [ "$key" = "SDF_DataRecordEnable" ] || [ "$key" = "Email_Enable" ] || [ "$key" = "Email_Include_Hostname" ] || [ "$key" = "Email_Use_HTML" ] || [ "$key" = "Email_Attach_Logs" ] || [ "$key" = "Email_Attach_CSV" ] || [ "$key" = "Test_ONLY_NVMe_Drives" ]; then
                value=$(echo "$value" | sed 's/[[:space:]]*#.*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^["'"'"']//;s/["'"'"']$//')
                if [[ "$value" =~ ^(true|false)$ ]]; then
                    case "$key" in
                        Use_SCT_Temperature_Data) Use_SCT_Temperature_Data="$value" ;;
                        SMR_Enable) SMR_Enable="$value" ;;
                        SMR_Update) SMR_Update="$value" ;;
                        SMR_Ignore_Alarm) SMR_Ignore_Alarm="$value" ;;
                        SDF_DataRecordEnable) SDF_DataRecordEnable="$value" ;;
                        Email_Enable) Email_Enable="$value" ;;
                        Email_Include_Hostname) Email_Include_Hostname="$value" ;;
                        Email_Use_HTML) Email_Use_HTML="$value" ;;
                        Email_Attach_Logs) Email_Attach_Logs="$value" ;;
                        Email_Attach_CSV) Email_Attach_CSV="$value" ;;
                        Test_ONLY_NVMe_Drives) Test_ONLY_NVMe_Drives="$value" ;;
                    esac
                fi
            elif [ "$key" = "Statistical_Data_File" ] || [ "$key" = "Email_To" ] || [ "$key" = "Email_From" ] || [ "$key" = "Email_Subject_Prefix" ] || [ "$key" = "Email_Level" ] || [ "$key" = "Short_SMART_Testing_Order" ] || [ "$key" = "Short_Drives_Test_Period" ] || [ "$key" = "Short_Drives_Tested_Days_of_the_Week" ] || [ "$key" = "Long_SMART_Testing_Order" ] || [ "$key" = "Long_Drives_Test_Period" ] || [ "$key" = "Long_Drives_Tested_Days_of_the_Week" ] || [ "$key" = "Ignore_Drives_List" ] || [ "$key" = "CSV_File_Owner" ] || [ "$key" = "CSV_File_Group" ] || [ "$key" = "CSV_File_Permissions" ]; then
                # Handle string values - remove quotes and comments but keep the text
                value=$(echo "$value" | sed 's/[[:space:]]*#.*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^["'"'"']//;s/["'"'"']$//')
                if [ -n "$value" ]; then
                    case "$key" in
                        Statistical_Data_File) 
                            # Expand $SCRIPT_DIR if present in the value
                            if [[ "$value" == *'$SCRIPT_DIR'* ]]; then
                                Statistical_Data_File="${value/\$SCRIPT_DIR/$SCRIPT_DIR}"
                            else
                                Statistical_Data_File="$value"
                            fi
                            ;;
                        Email_To) Email_To="$value" ;;
                        Email_From) Email_From="$value" ;;
                        Email_Subject_Prefix) Email_Subject_Prefix="$value" ;;
                        Email_Level) Email_Level="$value" ;;
                        Short_SMART_Testing_Order) Short_SMART_Testing_Order="$value" ;;
                        Short_Drives_Test_Period) Short_Drives_Test_Period="$value" ;;
                        Short_Drives_Tested_Days_of_the_Week) Short_Drives_Tested_Days_of_the_Week="$value" ;;
                        Long_SMART_Testing_Order) Long_SMART_Testing_Order="$value" ;;
                        Long_Drives_Test_Period) Long_Drives_Test_Period="$value" ;;
                        Long_Drives_Tested_Days_of_the_Week) Long_Drives_Tested_Days_of_the_Week="$value" ;;
                        Ignore_Drives_List) Ignore_Drives_List="$value" ;;
                        CSV_File_Owner) CSV_File_Owner="$value" ;;
                        CSV_File_Group) CSV_File_Group="$value" ;;
                        CSV_File_Permissions) CSV_File_Permissions="$value" ;;
                    esac
                fi
            else
                # Extract only the numeric value before any comment or quote
                value=$(echo "$value" | sed 's/[[:space:]]*#.*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^["'"'"']//;s/["'"'"']$//' | grep -o '^[0-9]\+')
                
                # Set the variable if it's one we recognize and has a valid numeric value
                if [ -n "$value" ] && [[ "$value" =~ ^[0-9]+$ ]]; then
                    case "$key" in
                        Drive_Temp_Warn) Drive_Temp_Warn="$value" ;;
                        Drive_Temp_Critical) Drive_Temp_Critical="$value" ;;
                        SSD_Temp_Warn) SSD_Temp_Warn="$value" ;;
                        SSD_Temp_Critical) SSD_Temp_Critical="$value" ;;
                        NVMe_Temp_Warn) NVMe_Temp_Warn="$value" ;;
                        NVMe_Temp_Critical) NVMe_Temp_Critical="$value" ;;
                        Drive_Temp_Warning_Delta) Drive_Temp_Warning_Delta="$value" ;;
                        SSD_Temp_Warning_Delta) SSD_Temp_Warning_Delta="$value" ;;
                        NVMe_Temp_Warning_Delta) NVMe_Temp_Warning_Delta="$value" ;;
                        SDF_DataPurgeDays) SDF_DataPurgeDays="$value" ;;
                        Short_Test_Mode) Short_Test_Mode="$value" ;;
                        Short_Drives_to_Test_Per_Day) Short_Drives_to_Test_Per_Day="$value" ;;
                        Short_Time_Delay_Between_Drives) Short_Time_Delay_Between_Drives="$value" ;;
                        Long_Test_Mode) Long_Test_Mode="$value" ;;
                        Long_Drives_to_Test_Per_Day) Long_Drives_to_Test_Per_Day="$value" ;;
                        Long_Time_Delay_Between_Drives) Long_Time_Delay_Between_Drives="$value" ;;
                    esac
                fi
            fi
        done < "$Config_File_Name"
    else
        echo "Config file not found: $Config_File_Name"
        echo "Using default temperature thresholds"
    fi
    
    echo "Temperature thresholds: HDD($Drive_Temp_Warn/$Drive_Temp_Critical°C) SSD($SSD_Temp_Warn/$SSD_Temp_Critical°C) NVMe($NVMe_Temp_Warn/$NVMe_Temp_Critical°C)"
    echo "SCT data usage: $Use_SCT_Temperature_Data (Deltas: HDD=$Drive_Temp_Warning_Delta, SSD=$SSD_Temp_Warning_Delta, NVMe=$NVMe_Temp_Warning_Delta)"
    echo "SMR detection: $SMR_Enable (Auto-update: $SMR_Update, Ignore alarms: $SMR_Ignore_Alarm)"
    echo "CSV data recording: $SDF_DataRecordEnable (File: $Statistical_Data_File, Purge: $SDF_DataPurgeDays days)"
    if [ "$SDF_DataRecordEnable" = "true" ]; then
        echo "CSV file ownership: Owner=${CSV_File_Owner:-root}, Group=${CSV_File_Group:-root}, Permissions=${CSV_File_Permissions:-644}"
    fi
    echo "Email notifications: $Email_Enable (To: $Email_To, Level: $Email_Level, HTML: $Email_Use_HTML)"
}

set -E -o functrace

failure(){
    echo "Script failed at line $1"
}

if test -e "/tmp/multi_report_omv_errors.txt"; then
    rm "/tmp/multi_report_omv_errors.txt"
fi

###### Root/Sudo Check
check_root_privileges() {
    if [ "$EUID" -ne 0 ]; then
        echo "This script requires root privileges for full functionality (SMART data access)."
        echo "Please run with sudo or as root:"
        echo "sudo $0 $*"
        echo ""
        echo "Continuing with limited functionality..."
        HAVE_ROOT=false
        return 1
    else
        HAVE_ROOT=true
        return 0
    fi
}

###### System Detection - OMV Version (Simplified)
detect_omv_system() {
    if [ -f "/etc/openmediavault/config.xml" ]; then
        # Use dpkg method (the only one that works reliably)
        OMV_VERSION=$(dpkg -l | grep openmediavault | head -1 | awk '{print $3}' 2>/dev/null || echo "Unknown")
        
        if [ "$OMV_VERSION" = "Unknown" ] || [ -z "$OMV_VERSION" ]; then
            OMV_VERSION="Unknown"
        fi
        
        echo "OpenMediaVault $OMV_VERSION detected"
        return 0
    else
        echo "ERROR: OpenMediaVault not detected. This script is designed for OMV systems."
        exit 1
    fi
}

###### Get OMV System Information
get_omv_system_info() {
    local hostname
    local kernel_version
    local uptime_info
    
    hostname=$(hostname)
    kernel_version=$(uname -r)
    uptime_info=$(uptime)
    
    echo "System: $hostname"
    echo "Kernel: $kernel_version" 
    echo "Uptime: $uptime_info"
    echo "Root privileges: $HAVE_ROOT"
    
    # Get OMV specific info
    if [ -x "/usr/sbin/omv-confdbadm" ] && [ "$HAVE_ROOT" = true ]; then
        echo "OMV Config accessible: Yes (via /usr/sbin/omv-confdbadm)"
    else
        echo "OMV Config accessible: No (requires root access and /usr/sbin/omv-confdbadm)"
    fi
}

###### Get Drive Information (OMV-specific)
get_omv_drives() {
    echo "=== Drive Detection ==="
    
    # Get all block devices
    lsblk -d -o NAME,SIZE,MODEL,SERIAL | grep -E '^sd[a-z]|^nvme[0-9]' | while read -r line; do
        echo "Drive found: $line"
    done
    
    echo ""
    echo "=== SMART Capable Drives ==="
    
    # Check SMART capability
    for drive in $(lsblk -dn -o NAME | grep -E '^sd[a-z]+$|^nvme[0-9]+n[0-9]+$'); do
        if [ "$HAVE_ROOT" = true ]; then
            if smartctl -i /dev/$drive >/dev/null 2>&1; then
                model=$(smartctl -i /dev/$drive | grep "Device Model\|Model Number" | cut -d: -f2 | xargs)
                serial=$(smartctl -i /dev/$drive | grep "Serial Number" | cut -d: -f2 | xargs)
                echo "✓ /dev/$drive - $model (S/N: $serial)"
            else
                echo "✗ /dev/$drive - SMART not available"
            fi
        else
            echo "? /dev/$drive - Requires root privileges for SMART access"
        fi
    done
}

###### CSV Statistical Data Functions
###### Set CSV file ownership and permissions
set_csv_file_ownership() {
    if [ "$SDF_DataRecordEnable" != "true" ] || [ ! -f "$Statistical_Data_File" ]; then
        return 0
    fi
    
    # Set file permissions
    if [ -n "$CSV_File_Permissions" ]; then
        chmod "$CSV_File_Permissions" "$Statistical_Data_File" 2>/dev/null || echo "Warning: Could not set permissions $CSV_File_Permissions on $Statistical_Data_File"
    fi
    
    # Set file ownership
    local chown_target=""
    
    if [ -n "$CSV_File_Owner" ] && [ -n "$CSV_File_Group" ]; then
        chown_target="$CSV_File_Owner:$CSV_File_Group"
    elif [ -n "$CSV_File_Owner" ]; then
        chown_target="$CSV_File_Owner"
    elif [ -n "$CSV_File_Group" ]; then
        chown_target=":$CSV_File_Group"
    fi
    
    if [ -n "$chown_target" ]; then
        if command -v chown >/dev/null 2>&1; then
            chown "$chown_target" "$Statistical_Data_File" 2>/dev/null || echo "Warning: Could not set ownership $chown_target on $Statistical_Data_File"
        else
            echo "Warning: chown command not available, cannot set ownership"
        fi
    fi
}

###### Initialize CSV file with header if it doesn't exist
initialize_csv_file() {
    if [ "$SDF_DataRecordEnable" != "true" ]; then
        return 0
    fi
    
    if ! test -e "$Statistical_Data_File"; then
        echo "Creating statistical data CSV file: $Statistical_Data_File"
        # Ensure directory exists
        mkdir -p "$(dirname "$Statistical_Data_File")"
        printf "Date,Time,Device ID,Mountpoint,Filesystem Name,Filesystem Type,OMV Tag,Drive Type,Serial Number,SMART Status,Temp,Power On Hours,Wear Level,Start Stop Count,Load Cycle,Spin Retry,Reallocated Sectors,Reallocated Sector Events,Pending Sectors,Offline Uncorrectable,UDMA CRC Errors,Seek Error Rate,Multi Zone Errors,Read Error Rate,SMR Status,Total MBytes Written,Total MBytes Read\n" > "$Statistical_Data_File"
        
        # Set ownership and permissions
        set_csv_file_ownership
        
        CSV_File_Created=true
    else
        CSV_File_Created=false
        # Purge old data if enabled
        purge_old_csv_data
        
        # Ensure ownership and permissions are correct on existing file
        set_csv_file_ownership
    fi
}

###### Purge old data from CSV file
purge_old_csv_data() {
    if [ "$SDF_DataRecordEnable" != "true" ] || [ -z "$SDF_DataPurgeDays" ]; then
        return 0
    fi
    
    if test -e "$Statistical_Data_File"; then
        echo "Checking for old CSV data to purge (older than $SDF_DataPurgeDays days)"
        
        # Calculate cutoff date (days ago from today)
        local cutoff_date
        cutoff_date=$(date -d "$SDF_DataPurgeDays days ago" +%Y%m%d)
        
        # Create temporary file
        local temp_file="/tmp/csv_purge_temp.csv"
        
        # Keep header and records newer than cutoff date
        head -1 "$Statistical_Data_File" > "$temp_file"
        awk -v cutoff="$cutoff_date" -F, 'NR>1 { 
            date_field = $1; 
            gsub(/-/, "", date_field); 
            if(date_field >= cutoff) print $0; 
        }' "$Statistical_Data_File" >> "$temp_file"
        
        # Replace original file if temp file has content
        if [ -s "$temp_file" ]; then
            cp "$temp_file" "$Statistical_Data_File"
            echo "Purged CSV data older than $SDF_DataPurgeDays days"
        fi
        rm -f "$temp_file"
    fi
}

###### Record drive data to CSV file
record_drive_data_csv() {
    if [ "$SDF_DataRecordEnable" != "true" ]; then
        return 0
    fi
    
    local drive="$1"
    local model="$2"
    local serial="$3"
    local smart_status="$4"
    local temp="$5"
    local power_hours="$6"
    local reallocated="$7"
    local pending="$8"
    local uncorrectable="$9"
    local smr_status="${10}"
    
    # Determine drive type
    local drive_type="HDD"
    if echo "$model" | grep -qi "ssd\|solid"; then
        drive_type="SSD"
    elif echo "$drive" | grep -q "nvme"; then
        drive_type="NVMe"
    fi
    
    # Generate timestamp
    local datestamp=$(date +%Y-%m-%d)
    local timestamp=$(date +%H:%M:%S)
    
    # Get additional SMART data if available
    local wear_level="N/A"
    local start_stop="N/A"
    local load_cycle="N/A"
    local spin_retry="N/A"
    local realloc_events="N/A"
    local crc_errors="N/A"
    local seek_errors="N/A"
    local multi_zone="N/A"
    local read_error_rate="N/A"
    local total_written="N/A"
    local total_read="N/A"
    
    # Get additional SMART attributes if we have root access
    if [ "$HAVE_ROOT" = true ]; then
        local smart_attrs
        smart_attrs=$(smartctl -A /dev/$drive 2>/dev/null)
        
        if [ -n "$smart_attrs" ]; then
            start_stop=$(echo "$smart_attrs" | grep "Start_Stop_Count" | awk '{print $10}' | head -1)
            load_cycle=$(echo "$smart_attrs" | grep "Load_Cycle_Count" | awk '{print $10}' | head -1)
            spin_retry=$(echo "$smart_attrs" | grep "Spin_Retry_Count" | awk '{print $10}' | head -1)
            realloc_events=$(echo "$smart_attrs" | grep "Reallocated_Event_Count" | awk '{print $10}' | head -1)
            crc_errors=$(echo "$smart_attrs" | grep "UDMA_CRC_Error_Count" | awk '{print $10}' | head -1)
            seek_errors=$(echo "$smart_attrs" | grep "Seek_Error_Rate" | awk '{print $10}' | head -1)
            multi_zone=$(echo "$smart_attrs" | grep "Multi_Zone_Error_Rate" | awk '{print $10}' | head -1)
            read_error_rate=$(echo "$smart_attrs" | grep "Raw_Read_Error_Rate" | awk '{print $10}' | head -1)
            
            # SSD-specific attributes
            if [ "$drive_type" = "SSD" ]; then
                wear_level=$(echo "$smart_attrs" | grep -E "Wear_Leveling_Count|SSD_Life_Left|Percent_Lifetime_Remain" | awk '{print $10}' | head -1)
                total_written=$(echo "$smart_attrs" | grep -E "Total_LBAs_Written|Data_Units_Written" | awk '{print $10}' | head -1)
                total_read=$(echo "$smart_attrs" | grep -E "Total_LBAs_Read|Data_Units_Read" | awk '{print $10}' | head -1)
            fi
        fi
    fi
    
    # Clean up N/A values
    [ -z "$start_stop" ] && start_stop="N/A"
    [ -z "$load_cycle" ] && load_cycle="N/A"
    [ -z "$spin_retry" ] && spin_retry="N/A"
    [ -z "$realloc_events" ] && realloc_events="N/A"
    [ -z "$crc_errors" ] && crc_errors="N/A"
    [ -z "$seek_errors" ] && seek_errors="N/A"
    [ -z "$multi_zone" ] && multi_zone="N/A"
    [ -z "$read_error_rate" ] && read_error_rate="N/A"
    
    # Get filesystem information for this drive
    local fs_info
    fs_info=$(get_drive_filesystem_info "$drive")
    local mountpoint=$(echo "$fs_info" | cut -d'|' -f1)
    local fs_name=$(echo "$fs_info" | cut -d'|' -f2)
    local fs_type=$(echo "$fs_info" | cut -d'|' -f3)
    local omv_label=$(echo "$fs_info" | cut -d'|' -f4)
    
    # Write data to CSV
    printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n" \
        "$datestamp" "$timestamp" "$drive" "$mountpoint" "$fs_name" "$fs_type" "$omv_label" \
        "$drive_type" "$serial" "$smart_status" "$temp" "$power_hours" "$wear_level" \
        "$start_stop" "$load_cycle" "$spin_retry" "$reallocated" "$realloc_events" \
        "$pending" "$uncorrectable" "$crc_errors" "$seek_errors" "$multi_zone" \
        "$read_error_rate" "$smr_status" "$total_written" "$total_read" \
        >> "$Statistical_Data_File"
}

###### Get filesystem information for a drive
get_drive_filesystem_info() {
    local drive="$1"
    local mountpoint="N/A"
    local fs_name="N/A"
    local fs_type="N/A"
    local omv_label="N/A"
    
    # First, try to get info from the main partition (drive1, e.g., sda1, sdb1)
    local partition_name="${drive}1"
    local partition_info
    partition_info=$(lsblk -no MOUNTPOINT,FSTYPE,LABEL /dev/$partition_name 2>/dev/null | head -1)
    
    if [ -n "$partition_info" ]; then
        # Parse the partition information
        local mount_part=$(echo "$partition_info" | awk '{print $1}')
        local fs_part=$(echo "$partition_info" | awk '{print $2}')
        local label_part=$(echo "$partition_info" | awk '{print $3}')
        
        # Set mountpoint (keep full path, no truncation)
        if [ -n "$mount_part" ] && [ "$mount_part" != "" ]; then
            mountpoint="$mount_part"
        fi
        
        # Set filesystem type (raw value)
        if [ -n "$fs_part" ] && [ "$fs_part" != "" ]; then
            fs_type="$fs_part"
        fi
        
        # Note: We don't use filesystem label as fallback for OMV tag
        # OMV tag should only contain actual OMV tags/comments
    else
        # Fallback: check if the base drive has filesystem info (rare)
        partition_info=$(lsblk -no MOUNTPOINT,FSTYPE,LABEL /dev/$drive 2>/dev/null | head -1)
        
        if [ -n "$partition_info" ]; then
            local mount_part=$(echo "$partition_info" | awk '{print $1}')
            local fs_part=$(echo "$partition_info" | awk '{print $2}')
            local label_part=$(echo "$partition_info" | awk '{print $3}')
            
            [ -n "$mount_part" ] && mountpoint="$mount_part"
            [ -n "$fs_part" ] && fs_type="$fs_part"
            # Note: We don't use filesystem label as OMV tag fallback
        fi
    fi
    
    # Try to get OMV-specific filesystem name and tag/comment
    if [ -x "/usr/sbin/omv-confdbadm" ] && [ "$HAVE_ROOT" = true ]; then
        # Get the UUID of the filesystem
        local uuid
        if [ "$partition_name" != "${drive}1" ]; then
            uuid=$(lsblk -no UUID /dev/$drive 2>/dev/null)
        else
            uuid=$(lsblk -no UUID /dev/$partition_name 2>/dev/null)
        fi
        
        if [ -n "$uuid" ]; then
            # Try to get filesystem config from OMV (get all filesystem configs as JSON)
            local omv_all_configs
            omv_all_configs=$(/usr/sbin/omv-confdbadm read "conf.system.filesystem.mountpoint" 2>/dev/null)
            
            if [ -n "$omv_all_configs" ]; then
                # Find the filesystem entry that contains our UUID and extract the comment
                local omv_comment
                omv_comment=$(echo "$omv_all_configs" | grep -o '"fsname": "[^"]*'"$uuid"'[^"]*"[^}]*"comment": "[^"]*"' | sed 's/.*"comment": "\([^"]*\)".*/\1/' 2>/dev/null)
                
                if [ -n "$omv_comment" ] && [ "$omv_comment" != "" ]; then
                    omv_label="$omv_comment"
                fi
            fi
        fi
    fi
    
    # Set filesystem name based on filesystem label (user-friendly names like "data4", "parity")
    if [ "$fs_name" = "N/A" ]; then
        # First, try to get the filesystem label for a user-friendly name
        local fs_label=""
        if [ "$partition_name" != "${drive}1" ]; then
            fs_label=$(lsblk -no LABEL /dev/$drive 2>/dev/null | head -1)
        else
            fs_label=$(lsblk -no LABEL /dev/$partition_name 2>/dev/null | head -1)
        fi
        
        if [ -n "$fs_label" ] && [ "$fs_label" != "" ]; then
            fs_name="$fs_label"
        # Otherwise, fall back to a friendly version of the filesystem type
        elif [ "$fs_type" != "N/A" ]; then
            case "$fs_type" in
                "ext4") fs_name="EXT4 Filesystem" ;;
                "ext3") fs_name="EXT3 Filesystem" ;;
                "ext2") fs_name="EXT2 Filesystem" ;;
                "xfs") fs_name="XFS Filesystem" ;;
                "btrfs") fs_name="Btrfs Filesystem" ;;
                "ntfs") fs_name="NTFS Filesystem" ;;
                "vfat"|"fat32") fs_name="FAT32 Filesystem" ;;
                "exfat") fs_name="exFAT Filesystem" ;;
                "zfs") fs_name="ZFS Filesystem" ;;
                "swap") fs_name="Swap Space" ;;
                *) fs_name="$fs_type Filesystem" ;;
            esac
        fi
    fi
    
    # Normalize filesystem type to uppercase for consistency
    if [ "$fs_type" != "N/A" ]; then
        case "$fs_type" in
            "ext4") fs_type="EXT4" ;;
            "ext3") fs_type="EXT3" ;;
            "ext2") fs_type="EXT2" ;;
            "xfs") fs_type="XFS" ;;
            "btrfs") fs_type="Btrfs" ;;
            "ntfs") fs_type="NTFS" ;;
            "vfat"|"fat32") fs_type="FAT32" ;;
            "exfat") fs_type="exFAT" ;;
            "zfs") fs_type="ZFS" ;;
            "swap") fs_type="Swap" ;;
            *) fs_type=$(echo "$fs_type" | tr '[:lower:]' '[:upper:]') ;;
        esac
    fi
    
    # Return the four values: mountpoint|fs_name|fs_type|omv_label
    echo "$mountpoint|$fs_name|$fs_type|$omv_label"
}

###### Get SMART Data for All Drives (Enhanced with Test Analysis)
get_smart_data() {
    echo "=== SMART Drive Health Analysis ==="
    
    if [ "$HAVE_ROOT" != true ]; then
        echo "⚠ SMART data collection requires root privileges"
        return 1
    fi
    
    local drive_count=0
    local warning_count=0
    local critical_count=0
    
    # Arrays to track drive statuses
    declare -a critical_drives=()
    declare -a warning_drives=()
    declare -a healthy_drives=()
    
    for drive in $(lsblk -dn -o NAME | grep -E '^sd[a-z]+$|^nvme[0-9]+n[0-9]+$'); do
        drive_count=$((drive_count + 1))
        echo ""
        echo "--- Drive /dev/$drive ---"
        
        # Get basic drive info
        model=$(smartctl -i /dev/$drive | grep "Device Model\|Model Number" | cut -d: -f2 | xargs)
        serial=$(smartctl -i /dev/$drive | grep "Serial Number" | cut -d: -f2 | xargs)
        
        echo "Model: $model"
        echo "Serial: $serial"
        
        # Check for SMR drive
        smr_status=""
        if [ "$SMR_Enable" = "true" ] && [ -n "$serial" ]; then
            if check_for_smr "$serial" "$model"; then
                if [ "$SMR_Ignore_Alarm" = "true" ]; then
                    smr_status=" [SMR - Monitoring Only]"
                    echo "🟡 SMR Drive Detected (S/N: $serial) - Alarms disabled"
                else
                    smr_status=" [SMR - WARNING]"
                    echo "⚠️  SMR Drive Detected (S/N: $serial) - Not recommended for ZFS/RAID"
                    has_warnings=true
                    warning_details="$warning_details SMR drive detected;"
                fi
            else
                echo "✅ CMR Drive (Not SMR)"
            fi
        fi
        
        # Get SMART health status
        smart_status=$(smartctl -H /dev/$drive | grep "SMART overall-health" | cut -d: -f2 | xargs)
        if [ -z "$smart_status" ]; then
            smart_status=$(smartctl -H /dev/$drive | grep "SMART Health Status" | cut -d: -f2 | xargs)
        fi
        
        # Analyze health status
        health_status="UNKNOWN"
        if [ "$smart_status" = "PASSED" ]; then
            health_status="HEALTHY"
        elif [ "$smart_status" = "FAILED" ]; then
            health_status="CRITICAL"
        fi
        
        # Get power-on hours BEFORE using it
        power_hours=$(smartctl -A /dev/$drive | grep "Power_On_Hours" | awk '{print $10}')
        if [ -z "$power_hours" ]; then
            power_hours="N/A"
        fi
        
        # Get reallocated sectors BEFORE using it
        reallocated=$(smartctl -A /dev/$drive | grep "Reallocated_Sector_Ct" | awk '{print $10}')
        if [ -z "$reallocated" ]; then
            reallocated="N/A"
        fi
        
        # Get temperature and temperature thresholds from SMART - ENHANCED WITH SCT DATA
        temp=""
        temp_max_recorded=""  # Historical max from Min/Max field
        temp_threshold=""     # Actual warning threshold
        temp_limit=""         # Hard temperature limit
        temp_worst=""
        temp_raw=""
        threshold_source=""
        
        # First, try to get temperature from standard SMART attributes
        temp_lines=$(smartctl -A /dev/$drive | grep -i "temperature\|airflow")
        
        if [ -n "$temp_lines" ]; then
            # Find the best temperature line (prefer one with meaningful threshold)
            best_temp_line=""
            best_threshold=0
            
            while IFS= read -r line; do
                if [ -n "$line" ]; then
                    line_threshold=$(echo "$line" | awk '{print $7}')
                    line_name=$(echo "$line" | awk '{print $2}')
                    
                    # Prefer lines with meaningful thresholds (> 0)
                    if [ -n "$line_threshold" ] && [[ "$line_threshold" =~ ^[0-9]+$ ]] && [ "$line_threshold" -gt 0 ]; then
                        if [ "$line_threshold" -gt "$best_threshold" ]; then
                            best_temp_line="$line"
                            best_threshold="$line_threshold"
                        fi
                    elif [ -z "$best_temp_line" ]; then
                        # If no meaningful threshold found yet, use this line for temperature reading
                        best_temp_line="$line"
                    fi
                fi
            done <<< "$temp_lines"
            
            # Extract temperature data from the best line
            if [ -n "$best_temp_line" ]; then
                temp_raw=$(echo "$best_temp_line" | awk '{print $10}')
                temp_worst=$(echo "$best_temp_line" | awk '{print $6}')
                temp_threshold=$(echo "$best_temp_line" | awk '{print $7}')
                temp_attribute=$(echo "$best_temp_line" | awk '{print $2}')
                
                # Extract current temp from raw value
                if echo "$temp_raw" | grep -q "("; then
                    temp=$(echo "$temp_raw" | cut -d' ' -f1)
                    # Extract RECORDED max temperature if available (Min/Max format)
                    if echo "$temp_raw" | grep -q "/"; then
                        temp_max_recorded=$(echo "$temp_raw" | grep -o '/[0-9]\+' | cut -d'/' -f2 | head -1)
                    fi
                else
                    temp="$temp_raw"
                fi
            fi
        fi
        
        # Get SCT temperature data for REAL manufacturer limits
        sct_data=$(smartctl -x /dev/$drive 2>/dev/null | grep -A 15 "SCT Status Version\|SCT Temperature History")
        
        # Extract manufacturer temperature limits from SCT data
        sct_max_operating=""
        sct_temp_limit=""
        sct_recommended_max=""
        sct_under_over_count=""
        sct_current_temp=""
        sct_lifetime_min_max=""
        
        if [ -n "$sct_data" ]; then
            # Extract temperature violation counters
            sct_under_over_count=$(echo "$sct_data" | grep "Under/Over Temperature Limit Count:" | sed 's/.*Under\/Over Temperature Limit Count:[[:space:]]*\([0-9]*\/[0-9]*\).*/\1/')
            
            # Extract SCT current temperature (sometimes more accurate than SMART)
            sct_current_temp=$(echo "$sct_data" | grep "Current Temperature:" | grep -o '[0-9]\+' | head -1)
            
            # Extract lifetime min/max temperatures
            sct_lifetime_min_max=$(echo "$sct_data" | grep "Lifetime.*Min/Max Temperature:" | sed 's/.*Lifetime.*Min\/Max Temperature:[[:space:]]*\([0-9]*\/[0-9]*\).*/\1/')
            
            # Try different SCT temperature limit formats
            # Format 1: "Specified Max Operating Temperature: XX Celsius"
            sct_max_operating=$(echo "$sct_data" | grep "Specified Max Operating Temperature" | grep -o '[0-9]\+' | head -1)
            
            # Format 2: "Min/Max Temperature Limit: XX/YY Celsius" 
            sct_temp_limit=$(echo "$sct_data" | grep "Min/Max Temperature Limit" | grep -o '/[0-9]\+' | cut -d'/' -f2 | head -1)
            
            # Format 3: "Min/Max recommended Temperature: XX/YY Celsius"
            sct_recommended_max=$(echo "$sct_data" | grep "Min/Max recommended Temperature" | grep -o '/[0-9]\+' | cut -d'/' -f2 | head -1)
            
            # Format 4: Alternative parsing for "Min/Max recommended Temperature: 0/60 Celsius"
            if [ -z "$sct_recommended_max" ]; then
                sct_recommended_max=$(echo "$sct_data" | grep "Min/Max recommended Temperature:" | sed 's/.*Min\/Max recommended Temperature:[[:space:]]*[0-9]*\/\([0-9]\+\).*/\1/')
                # Validate it's actually a number
                if ! [[ "$sct_recommended_max" =~ ^[0-9]+$ ]]; then
                    sct_recommended_max=""
                fi
            fi
            
            # Format 5: Alternative parsing for "Min/Max Temperature Limit: -41/85 Celsius"
            if [ -z "$sct_temp_limit" ]; then
                sct_temp_limit=$(echo "$sct_data" | grep "Min/Max Temperature Limit:" | sed 's/.*Min\/Max Temperature Limit:[[:space:]]*-\?[0-9]*\/\([0-9]\+\).*/\1/')
                # Validate it's actually a number
                if ! [[ "$sct_temp_limit" =~ ^[0-9]+$ ]]; then
                    sct_temp_limit=""
                fi
            fi
            
            # Use SCT current temperature if available and SMART temp is missing
            if [ -z "$temp" ] && [ -n "$sct_current_temp" ] && [[ "$sct_current_temp" =~ ^[0-9]+$ ]]; then
                temp="$sct_current_temp"
                threshold_source="SCT Temperature Reading"
            fi
            
            # Use the best SCT temperature limit we found - BUT ONLY if user enabled SCT usage
            if [ "$Use_SCT_Temperature_Data" = "true" ]; then
                if [ -n "$sct_max_operating" ] && [[ "$sct_max_operating" =~ ^[0-9]+$ ]] && [ "$sct_max_operating" -ge 40 ]; then
                    temp_threshold="$sct_max_operating"
                    threshold_source="SCT Max Operating"
                elif [ -n "$sct_recommended_max" ] && [[ "$sct_recommended_max" =~ ^[0-9]+$ ]] && [ "$sct_recommended_max" -ge 40 ]; then
                    temp_threshold="$sct_recommended_max"
                    threshold_source="SCT Recommended"
                elif [ -n "$sct_temp_limit" ] && [[ "$sct_temp_limit" =~ ^[0-9]+$ ]] && [ "$sct_temp_limit" -ge 40 ]; then
                    temp_threshold="$sct_temp_limit"
                    threshold_source="SCT Limit"
                elif [ -n "$temp_threshold" ] && [[ "$temp_threshold" =~ ^[0-9]+$ ]] && [ "$temp_threshold" -gt 0 ] && [ "$temp_threshold" -ge 40 ]; then
                    threshold_source="SMART ($temp_attribute)"
                fi
            else
                # SCT disabled by user - only use SMART thresholds if available
                if [ -n "$temp_threshold" ] && [[ "$temp_threshold" =~ ^[0-9]+$ ]] && [ "$temp_threshold" -gt 0 ] && [ "$temp_threshold" -ge 40 ]; then
                    threshold_source="SMART ($temp_attribute)"
                fi
            fi
        fi
        
        # Manufacturer-specific defaults when no SCT/SMART data available OR when SCT data is unreasonable
        if [ -z "$temp_threshold" ] || [ "$temp_threshold" = "0" ] || ([ -n "$temp_threshold" ] && [[ "$temp_threshold" =~ ^[0-9]+$ ]] && [ "$temp_threshold" -lt 40 ]); then
            if echo "$model" | grep -qi "seagate\|ST[0-9]"; then
                temp_threshold=60
                threshold_source="Seagate Default"
            elif echo "$model" | grep -qi "toshiba"; then
                temp_threshold=55
                threshold_source="Toshiba Default"
            elif echo "$model" | grep -qi "western\|WDC\|WD"; then
                temp_threshold=60
                threshold_source="WD Default"  
            elif echo "$model" | grep -qi "samsung"; then
                if echo "$model" | grep -qi "ssd"; then
                    temp_threshold=70
                    threshold_source="Samsung SSD Default"
                else
                    temp_threshold=55
                    threshold_source="Samsung HDD Default"
                fi
            else
                temp_threshold=""  # Will be set by drive type logic below
            fi
        fi

        # Determine drive type and set final thresholds
        if echo "$model" | grep -qi "ssd\|solid"; then
            drive_type="SSD"
            if [ -n "$temp_threshold" ] && [[ "$temp_threshold" =~ ^[0-9]+$ ]] && [ "$temp_threshold" -ge 40 ] && echo "$threshold_source" | grep -q "SCT"; then
                # Using SCT manufacturer data - apply user-configurable warning delta
                temp_critical=$temp_threshold
                temp_warn=$((temp_threshold - SSD_Temp_Warning_Delta))
                # Ensure warning temp doesn't go below reasonable minimum
                if [ "$temp_warn" -lt 30 ]; then
                    temp_warn=30
                fi
                threshold_source="$threshold_source (Δ$SSD_Temp_Warning_Delta°C)"
            else
                # Using user configuration - use explicit warn/critical values (no delta)
                temp_warn="$SSD_Temp_Warn"
                temp_critical="$SSD_Temp_Critical"
                temp_threshold="$SSD_Temp_Critical"
                threshold_source="User Config (SSD)"
            fi
        elif echo "$drive" | grep -q "nvme"; then
            drive_type="NVMe"
            if [ -n "$temp_threshold" ] && [[ "$temp_threshold" =~ ^[0-9]+$ ]] && [ "$temp_threshold" -ge 40 ] && echo "$threshold_source" | grep -q "SCT"; then
                # Using SCT manufacturer data - apply user-configurable warning delta
                temp_critical=$temp_threshold
                temp_warn=$((temp_threshold - NVMe_Temp_Warning_Delta))
                # Ensure warning temp doesn't go below reasonable minimum
                if [ "$temp_warn" -lt 40 ]; then
                    temp_warn=40
                fi
                threshold_source="$threshold_source (Δ$NVMe_Temp_Warning_Delta°C)"
            else
                # Using user configuration - use explicit warn/critical values (no delta)
                temp_warn="$NVMe_Temp_Warn"
                temp_critical="$NVMe_Temp_Critical"
                temp_threshold="$NVMe_Temp_Critical"
                threshold_source="User Config (NVMe)"
            fi
        else
            drive_type="HDD"
            if [ -n "$temp_threshold" ] && [[ "$temp_threshold" =~ ^[0-9]+$ ]] && [ "$temp_threshold" -ge 40 ] && echo "$threshold_source" | grep -q "SCT"; then
                # Using SCT manufacturer data - apply user-configurable warning delta
                temp_critical=$temp_threshold
                temp_warn=$((temp_threshold - Drive_Temp_Warning_Delta))
                # Ensure warning temp doesn't go below reasonable minimum
                if [ "$temp_warn" -lt 25 ]; then
                    temp_warn=25
                fi
                threshold_source="$threshold_source (Δ$Drive_Temp_Warning_Delta°C)"
            else
                # Using user configuration - use explicit warn/critical values (no delta)
                temp_warn="$Drive_Temp_Warn"
                temp_critical="$Drive_Temp_Critical"
                temp_threshold="$Drive_Temp_Critical"
                threshold_source="User Config (HDD)"
            fi
        fi
        
        # Analyze current temperature status
        temp_status="OK"
        if [ -n "$temp" ] && [[ "$temp" =~ ^[0-9]+$ ]] && [ "$temp" -gt 0 ]; then
            if [ "$temp" -ge "$temp_critical" ]; then
                temp_status="CRITICAL"
            elif [ "$temp" -ge "$temp_warn" ]; then
                temp_status="WARNING"
            fi
            
            # Calculate temperature margin - ALWAYS show threshold info
            temp_margin=""
            if [ -n "$temp_threshold" ] && [[ "$temp_threshold" =~ ^[0-9]+$ ]] && [ "$temp_threshold" -gt 0 ]; then
                margin=$((temp_threshold - temp))
                if [ "$temp" -ge "$temp_threshold" ]; then
                    temp_margin=" (${temp_threshold}°C ${threshold_source} EXCEEDED by $((temp - temp_threshold))°C)"
                else
                    temp_margin=" (${temp_threshold}°C ${threshold_source}, ${margin}°C margin)"
                fi
            fi
            
            # Add RECORDED max temp info if available (just for reference)
            max_temp_info=""
            if [ -n "$temp_max_recorded" ] && [[ "$temp_max_recorded" =~ ^[0-9]+$ ]]; then
                max_temp_info=", Recorded max: ${temp_max_recorded}°C"
            fi
            
            # Add SCT lifetime temperature info if available
            lifetime_temp_info=""
            if [ -n "$sct_lifetime_min_max" ] && [[ "$sct_lifetime_min_max" =~ ^[0-9]+/[0-9]+$ ]]; then
                lifetime_max=$(echo "$sct_lifetime_min_max" | cut -d'/' -f2)
                if [ -n "$lifetime_max" ] && [[ "$lifetime_max" =~ ^[0-9]+$ ]]; then
                    lifetime_temp_info=", Lifetime max: ${lifetime_max}°C"
                fi
            fi
            
            # Add temperature violation counter info - ONLY if we have valid SCT temperature limits
            violation_info=""
            if [ -n "$sct_under_over_count" ] && [[ "$sct_under_over_count" =~ ^[0-9]+/[0-9]+$ ]]; then
                # Only show violations if we actually found valid SCT temperature limits
                # Check if we have any meaningful SCT temperature thresholds
                has_valid_sct_limits=false
                if [ -n "$sct_max_operating" ] && [[ "$sct_max_operating" =~ ^[0-9]+$ ]] && [ "$sct_max_operating" -ge 40 ]; then
                    has_valid_sct_limits=true
                elif [ -n "$sct_recommended_max" ] && [[ "$sct_recommended_max" =~ ^[0-9]+$ ]] && [ "$sct_recommended_max" -ge 40 ]; then
                    has_valid_sct_limits=true
                elif [ -n "$sct_temp_limit" ] && [[ "$sct_temp_limit" =~ ^[0-9]+$ ]] && [ "$sct_temp_limit" -ge 40 ]; then
                    has_valid_sct_limits=true
                fi
                
                # Only show violation info if we have valid SCT limits AND threshold_source contains "SCT"
                if [ "$has_valid_sct_limits" = true ] && echo "$threshold_source" | grep -q "SCT"; then
                    under_count=$(echo "$sct_under_over_count" | cut -d'/' -f1)
                    over_count=$(echo "$sct_under_over_count" | cut -d'/' -f2)
                    
                    if [ "$over_count" -gt 0 ] || [ "$under_count" -gt 0 ]; then
                        if [ "$over_count" -gt 0 ] && [ "$under_count" -gt 0 ]; then
                            violation_info=", Violations: ${under_count} under/${over_count} over limit"
                            # Escalate status based on violation severity
                            if [ "$over_count" -gt 10000 ]; then
                                temp_status="CRITICAL"  # Massive violation count
                            elif [ "$over_count" -gt 100 ]; then
                                temp_status="WARNING"   # Significant violations
                            fi
                        elif [ "$over_count" -gt 0 ]; then
                            violation_info=", Over-temp violations: ${over_count}"
                            # Escalate status based on violation severity
                            if [ "$over_count" -gt 100000 ]; then
                                temp_status="CRITICAL"  # Extreme violation count
                            elif [ "$over_count" -gt 10000 ]; then
                                temp_status="CRITICAL"  # Massive violation count
                            elif [ "$over_count" -gt 100 ]; then
                                temp_status="WARNING"   # Significant violations
                            fi
                        elif [ "$under_count" -gt 0 ]; then
                            violation_info=", Under-temp violations: ${under_count}"
                            # Under-temp is usually less critical
                            if [ "$under_count" -gt 1000 ]; then
                                temp_status="WARNING"
                            fi
                        fi
                    else
                        violation_info=", No temp violations"
                    fi
                fi
                # If no valid SCT limits, don't show violation info at all
            fi
            
            echo "Temperature: ${temp}°C [$temp_status]${temp_margin}${max_temp_info}${lifetime_temp_info}${violation_info}"
        else
            echo "Temperature: N/A"
        fi
        echo "Power-On Hours: $power_hours"
        echo "Reallocated Sectors: $reallocated"
        
        # Enhanced SMART attribute analysis
        local has_warnings=false
        local has_critical=false
        local warning_details=""
        local critical_reasons=""
        
        # Get full SMART attribute output
        smart_attributes=$(smartctl -A /dev/$drive)
        
        echo "Checking critical SMART attributes..."
        
        # Current Pending Sector Count (ID 197) - HIGH PRIORITY
        pending_sectors=$(echo "$smart_attributes" | grep "Current_Pending_Sector" | awk '{print $10}')
        if [ -n "$pending_sectors" ] && [ "$pending_sectors" -gt 0 ]; then
            if [ "$pending_sectors" -gt 100 ]; then
                echo "  🚨 CRITICAL: Pending Sectors: $pending_sectors (drive failing!)"
                has_critical=true
                critical_reasons="$critical_reasons Pending sectors: $pending_sectors;"
            elif [ "$pending_sectors" -gt 10 ]; then
                echo "  🟠 HIGH: Pending Sectors: $pending_sectors (monitor closely)"
                has_warnings=true
                warning_details="$warning_details Pending sectors: $pending_sectors;"
            else
                echo "  🟡 LOW: Pending Sectors: $pending_sectors (minor concern)"
                has_warnings=true
                warning_details="$warning_details Minor pending sectors: $pending_sectors;"
            fi
        fi
        
        # Uncorrectable Sector Count (ID 198) - HIGH PRIORITY
        uncorrectable=$(echo "$smart_attributes" | grep "Offline_Uncorrectable" | awk '{print $10}')
        if [ -n "$uncorrectable" ] && [ "$uncorrectable" -gt 0 ]; then
            if [ "$uncorrectable" -gt 50 ]; then
                echo "  🚨 CRITICAL: Uncorrectable Sectors: $uncorrectable"
                has_critical=true
                critical_reasons="$critical_reasons Uncorrectable sectors: $uncorrectable;"
            else
                echo "  🟠 MODERATE: Uncorrectable Sectors: $uncorrectable"
                has_warnings=true
                warning_details="$warning_details Uncorrectable sectors: $uncorrectable;"
            fi
        fi
        
        # Reallocated Sector Count (ID 5) - MODERATE PRIORITY
        reallocated_raw=$(echo "$smart_attributes" | grep "Reallocated_Sector_Ct" | awk '{print $10}')
        if [ -n "$reallocated_raw" ] && [ "$reallocated_raw" -gt 0 ]; then
            if [ "$reallocated_raw" -gt 50 ]; then
                echo "  🟠 HIGH: Reallocated Sectors: $reallocated_raw"
                has_warnings=true
                warning_details="$warning_details High reallocated sectors: $reallocated_raw;"
            else
                echo "  🟢 INFO: Reallocated Sectors: $reallocated_raw (normal wear)"
            fi
        fi
        
        # Check for FAILING_NOW (CRITICAL)
        if echo "$smart_attributes" | grep -q "FAILING_NOW"; then
            failing_attrs=$(echo "$smart_attributes" | grep "FAILING_NOW" | awk '{print $2}')
            echo "  🚨 CRITICAL: Attributes currently failing: $failing_attrs"
            has_critical=true
            critical_reasons="$critical_reasons FAILING NOW: $failing_attrs;"
        fi
        
        # Check for In_the_past (INFORMATIONAL)
        if echo "$smart_attributes" | grep -q "In_the_past"; then
            past_failing=$(echo "$smart_attributes" | grep "In_the_past" | awk '{print $2}')
            if echo "$past_failing" | grep -qi "temperature\|airflow"; then
                echo "  ℹ️  INFO: Temperature exceeded threshold in past: $past_failing"
                echo "       (Historical - not immediate concern)"
            else
                echo "  🟡 PAST: Attributes that failed previously: $past_failing"
                has_warnings=true
                warning_details="$warning_details Past issues: $past_failing;"
            fi
        fi
        
        # SMART Self-Test Analysis (keeping your existing code)
        echo "Checking SMART test history..."
        selftest_json=$(smartctl -l selftest --json=c /dev/$drive 2>/dev/null)
        
        if [ -n "$selftest_json" ] && echo "$selftest_json" | jq -e '.ata_smart_self_test_log.standard.table' >/dev/null 2>&1; then
            # Get the most recent tests using jq
            short_test=$(echo "$selftest_json" | jq -r '.ata_smart_self_test_log.standard.table[]? | select(.type.string | test("Short offline")) | [.status.string, .lifetime_hours] | @tsv' | head -1)
            long_test=$(echo "$selftest_json" | jq -r '.ata_smart_self_test_log.standard.table[]? | select(.type.string | test("Extended offline")) | [.status.string, .lifetime_hours] | @tsv' | head -1)
            
            # Analyze Short Test (with Samsung SSD timeline fix)
            if [ -n "$short_test" ]; then
                short_status=$(echo "$short_test" | cut -f1)
                short_lifetime=$(echo "$short_test" | cut -f2)
                
                # Special handling for Samsung SSDs and other drives with timeline issues
                timeline_issue=false
                if echo "$model" | grep -qi "samsung.*ssd\|840.*EVO\|850.*EVO\|860.*EVO\|970.*EVO"; then
                    timeline_issue=true
                    echo "  ℹ️  Samsung SSD detected - timeline may be unreliable"
                elif [ -n "$power_hours" ] && [ "$power_hours" != "N/A" ] && [ -n "$short_lifetime" ] && \
                     [[ "$power_hours" =~ ^[0-9]+$ ]] && [[ "$short_lifetime" =~ ^[0-9]+$ ]] && \
                     [ "$short_lifetime" -gt "$power_hours" ]; then
                    timeline_issue=true
                    echo "  ℹ️  Timeline inconsistency detected (common with some drives)"
                fi
                
                if [ "$timeline_issue" = true ]; then
                    echo "  📊 Short test status: $short_status"
                    echo "     Test logged at $short_lifetime hours (timeline unreliable)"
                    echo "     Drive lifetime: $power_hours hours"
                    
                    if echo "$short_status" | grep -q "Completed without error"; then
                        echo "  ✅ Last short test completed successfully"
                        echo "     Note: Cannot determine actual test age due to firmware quirk"
                    elif echo "$short_status" | grep -q "Aborted by host"; then
                        echo "  ⚠️  Last short test was aborted by host"
                        echo "     Recommend running a new short test"
                        has_warnings=true
                        warning_details="$warning_details Short test aborted;"
                    elif echo "$short_status" | grep -q "Interrupted"; then
                        echo "  ⚠️  Last short test was interrupted"
                        echo "     Recommend running a new short test"
                        has_warnings=true
                        warning_details="$warning_details Short test interrupted;"
                    else
                        echo "  🟡 Short test status: $short_status"
                        echo "     Recommend running a new short test to verify current status"
                        has_warnings=true
                        warning_details="$warning_details Short test status unclear;"
                    fi
                elif [ -n "$power_hours" ] && [ "$power_hours" != "N/A" ] && [ -n "$short_lifetime" ] && \
                     [[ "$power_hours" =~ ^[0-9]+$ ]] && [[ "$short_lifetime" =~ ^[0-9]+$ ]] && \
                     [ "$power_hours" -gt 0 ] && [ "$short_lifetime" -gt 0 ]; then
                    
                    # Normal timeline calculation for drives without known issues
                    short_hours_ago=$((power_hours - short_lifetime))
                    if [ "$short_hours_ago" -ge 0 ]; then
                        short_days_ago=$((short_hours_ago / 24))
                        
                        if echo "$short_status" | grep -q "Completed without error"; then
                            if [ "$short_days_ago" -gt 30 ]; then
                                echo "  ⚠️  Short test: $short_days_ago days old (overdue - recommend monthly)"
                                has_warnings=true
                                warning_details="$warning_details Short test overdue;"
                            else
                                echo "  ✅ Short test: Recent and successful ($short_days_ago days ago)"
                            fi
                        elif echo "$short_status" | grep -q "Aborted by host"; then
                            echo "  ⚠️  Short test: Aborted by host ($short_days_ago days ago)"
                            has_warnings=true
                            warning_details="$warning_details Short test issues;"
                        elif echo "$short_status" | grep -q "Interrupted"; then
                            echo "  ⚠️  Short test: Interrupted ($short_days_ago days ago)"
                            has_warnings=true
                            warning_details="$warning_details Short test issues;"
                        else
                            echo "  🟡 Short test: $short_status ($short_days_ago days ago)"
                        fi
                    else
                        echo "  🟡 Short test: Cannot calculate age (power_hours: $power_hours, lifetime: $short_lifetime)"
                    fi
                else
                    echo "  🟡 Short test: Found but cannot calculate age (power_hours: $power_hours, lifetime: $short_lifetime)"
                fi
            else
                echo "  ❌ No short test history found - recommend running one"
                has_warnings=true
                warning_details="$warning_details No short test history;"
            fi
            
            # Analyze Extended Test (with Samsung SSD timeline fix)
            if [ -n "$long_test" ]; then
                long_status=$(echo "$long_test" | cut -f1)
                long_lifetime=$(echo "$long_test" | cut -f2)
                
                # Special handling for Samsung SSDs and other drives with timeline issues
                timeline_issue=false
                if echo "$model" | grep -qi "samsung.*ssd\|840.*EVO\|850.*EVO\|860.*EVO\|970.*EVO"; then
                    timeline_issue=true
                    echo "  ℹ️  Samsung SSD detected - timeline may be unreliable"
                elif [ -n "$power_hours" ] && [ "$power_hours" != "N/A" ] && [ -n "$long_lifetime" ] && \
                     [[ "$power_hours" =~ ^[0-9]+$ ]] && [[ "$long_lifetime" =~ ^[0-9]+$ ]] && \
                     [ "$long_lifetime" -gt "$power_hours" ]; then
                    timeline_issue=true
                    echo "  ℹ️  Timeline inconsistency detected (common with some drives)"
                fi
                
                if [ "$timeline_issue" = true ]; then
                    echo "  📊 Extended test status: $long_status"
                    echo "     Test logged at $long_lifetime hours (timeline unreliable)"
                    echo "     Drive lifetime: $power_hours hours"
                    
                    if echo "$long_status" | grep -q "Completed without error"; then
                        echo "  ✅ Last extended test completed successfully"
                        echo "     Note: Cannot determine actual test age due to firmware quirk"
                    elif echo "$long_status" | grep -q "Aborted by host"; then
                        echo "  ⚠️  Last extended test was aborted by host"
                        echo "     Recommend running a new extended test"
                        has_warnings=true
                        warning_details="$warning_details Extended test aborted;"
                    elif echo "$long_status" | grep -q "Interrupted"; then
                        echo "  ⚠️  Last extended test was interrupted"
                        echo "     Recommend running a new extended test"
                        has_warnings=true
                        warning_details="$warning_details Extended test interrupted;"
                    else
                        echo "  🟡 Extended test status: $long_status"
                        echo "     Recommend running a new extended test to verify current status"
                        has_warnings=true
                        warning_details="$warning_details Extended test status unclear;"
                    fi
                elif [ -n "$power_hours" ] && [ "$power_hours" != "N/A" ] && [ -n "$long_lifetime" ] && \
                     [[ "$power_hours" =~ ^[0-9]+$ ]] && [[ "$long_lifetime" =~ ^[0-9]+$ ]] && \
                     [ "$power_hours" -gt 0 ] && [ "$long_lifetime" -gt 0 ]; then
                    
                    # Normal timeline calculation for drives without known issues
                    long_hours_ago=$((power_hours - long_lifetime))
                    long_days_ago=$((long_hours_ago / 24))
                    
                    if echo "$long_status" | grep -q "Completed without error"; then
                        if [ "$long_days_ago" -gt 365 ]; then
                            echo "  🚨 Extended test: $long_days_ago days old (critical - recommend yearly)"
                            has_warnings=true
                            warning_details="$warning_details Extended test overdue ($long_days_ago days);"
                        elif [ "$long_days_ago" -gt 180 ]; then
                            echo "  ⚠️  Extended test: $long_days_ago days old (overdue - recommend 6 months)"
                            has_warnings=true
                            warning_details="$warning_details Extended test overdue ($long_days_ago days);"
                        else
                            echo "  ✅ Extended test: Recent and successful ($long_days_ago days ago)"
                        fi
                    elif echo "$long_status" | grep -q "Aborted by host"; then
                        echo "  ⚠️  Extended test: Aborted by host ($long_days_ago days ago)"
                        has_warnings=true
                        warning_details="$warning_details Extended test issues;"
                    elif echo "$long_status" | grep -q "Interrupted"; then
                        echo "  ⚠️  Extended test: Interrupted ($long_days_ago days ago)"
                        has_warnings=true
                        warning_details="$warning_details Extended test issues;"
                    else
                        echo "  🟡 Extended test: $long_status ($long_days_ago days ago)"
                    fi
                else
                    echo "  🟡 Extended test: Found but cannot calculate age (power_hours: $power_hours, lifetime: $long_lifetime)"
                fi
            else
                echo "  ❌ No extended test history found - recommend running one"
                has_warnings=true
                warning_details="$warning_details No extended test history;"
            fi
        else
            echo "  ❌ No SMART test log available or JSON parsing failed"
        fi
        
        # Categorize this drive (ONLY ONCE)
        if [ "$has_critical" = true ]; then
            echo "  🚨 CRITICAL DRIVE - Replace immediately!"
            critical_drives+=("/dev/$drive:$model$smr_status:$critical_reasons")
            critical_count=$((critical_count + 1))
        elif [ "$has_warnings" = true ]; then
            echo "  📋 Summary: $warning_details"
            warning_drives+=("/dev/$drive:$model$smr_status:$warning_details")
            warning_count=$((warning_count + 1))
        else
            echo "  ✓ Drive appears healthy"
            healthy_drives+=("/dev/$drive:$model$smr_status")
        fi
        
        # Record drive data to CSV file
        local csv_smr_status="CMR"
        if echo "$smr_status" | grep -q "SMR"; then
            csv_smr_status="SMR"
        fi
        record_drive_data_csv "$drive" "$model" "$serial" "$smart_status" "$temp" "$power_hours" "$reallocated" "$pending_sectors" "$uncorrectable" "$csv_smr_status"
    done
    
    echo ""
    echo "=== SMART Summary ==="
    echo "Total drives analyzed: $drive_count"
    echo "Healthy drives: ${#healthy_drives[@]}"
    echo "Warning drives: ${#warning_drives[@]}"
    echo "Critical drives: ${#critical_drives[@]}"
    
    # List critical drives
    if [ "${#critical_drives[@]}" -gt 0 ]; then
        echo ""
        echo "🚨 CRITICAL DRIVES (Replace immediately!):"
        for drive_info in "${critical_drives[@]}"; do
            IFS=':' read -r drive model reasons <<< "$drive_info"
            echo "  • $drive - $model"
            echo "    Reasons: $reasons"
        done
    fi
    
    # List warning drives
    if [ "${#warning_drives[@]}" -gt 0 ]; then
        echo ""
        echo "⚠️  WARNING DRIVES (Monitor closely):"
        for drive_info in "${warning_drives[@]}"; do
            IFS=':' read -r drive model issues <<< "$drive_info"
            echo "  • $drive - $model"
            echo "    Issues: $issues"
        done
    fi
    
    echo ""
    echo "SMART Test Recommendations:"
    echo "- Run short tests monthly: sudo smartctl -t short /dev/sdX"
    echo "- Run extended tests every 6 months: sudo smartctl -t long /dev/sdX"
    echo "- Check test progress: sudo smartctl -c /dev/sdX"
    echo ""
    echo "SMR Drive Information:"
    echo "- SMR (Shingled Magnetic Recording) drives overlap tracks to increase capacity"
    echo "- Not recommended for ZFS, RAID, or intensive random write workloads"
    echo "- Better suited for backup/archive use with sequential writes"
    echo "- Database maintained by Basil Hendroff with community contributions"
    echo ""
    echo "Known Issues:"
    echo "- Samsung SSDs may show unreliable test timestamps due to firmware quirks"
    echo "- Test completion status is still reliable, just not the timing"
    echo "- For Samsung SSDs, focus on test status rather than age"
    
    if [ "${#critical_drives[@]}" -gt 0 ]; then
        echo "🚨 CRITICAL: Immediate attention required!"
        return 2
    elif [ "${#warning_drives[@]}" -gt 0 ]; then
        echo "⚠ WARNING: Monitoring recommended"
        return 1
    else
        echo "✓ All drives healthy"
        return 0
    fi
}

###### Get Filesystem Status (replaces ZFS pool capacity)
get_filesystem_status() {
    echo "=== Filesystem Usage ==="
    df -h | grep -E '^/dev/' | while read -r filesystem size used avail percent mountpoint; do
        # Color code based on usage percentage
        usage_num=$(echo "$percent" | sed 's/%//')
        if [ "$usage_num" -ge 95 ]; then
            status="CRITICAL"
        elif [ "$usage_num" -ge 85 ]; then
            status="WARNING"
        else
            status="OK"
        fi
        
        echo "Filesystem: $filesystem [$status]"
        echo "  Size: $size"
        echo "  Used: $used ($percent)"
        echo "  Available: $avail"
        echo "  Mounted: $mountpoint"
        echo ""
    done
}

###### Get OMV Configuration Info
get_omv_config_info() {
    echo "=== OMV Configuration Status ==="
    
    if [ -f "/etc/openmediavault/config.xml" ]; then
        config_size=$(ls -lh /etc/openmediavault/config.xml | awk '{print $5}')
        config_date=$(ls -l /etc/openmediavault/config.xml | awk '{print $6, $7, $8}')
        echo "Config file size: $config_size"
        echo "Config file date: $config_date"
    else
        echo "Config file not found"
    fi
    
    # Check if OMV services are running
    if systemctl is-active --quiet openmediavault-engined; then
        echo "OMV Engine: Running"
    else
        echo "OMV Engine: Not running"
    fi
    
    if systemctl is-active --quiet nginx; then
        echo "Web interface: Running"
    else
        echo "Web interface: Not running"
    fi
}

###### Generate Summary Report
generate_summary_report() {
    echo ""
    echo "================================================"
    echo "        MULTI-REPORT OMV SUMMARY"
    echo "================================================"
    echo "System: $(hostname) - OpenMediaVault $OMV_VERSION"
    echo "Generated: $(date)"
    echo ""
    
    # System health
    if systemctl is-active --quiet openmediavault-engined; then
        echo "System Status: ✓ OMV Services Running"
    else
        echo "System Status: ✗ OMV Services Issue"
    fi
    
    # Drive count
    drive_count=$(lsblk -dn -o NAME | grep -E '^sd[a-z]+$|^nvme[0-9]+n[0-9]+$' | wc -l)
    echo "Monitored Drives: $drive_count"
    
    # Filesystem warnings
    warning_fs=$(df -h | grep -E '^/dev/' | awk '{print $5}' | sed 's/%//' | awk '$1 >= 85' | wc -l)
    if [ "$warning_fs" -gt 0 ]; then
        echo "Filesystem Warnings: $warning_fs filesystems above 85% usage"
    else
        echo "Filesystem Status: ✓ All filesystems healthy"
    fi
    
    # CSV data recording status
    if [ "$SDF_DataRecordEnable" = "true" ]; then
        if [ "$CSV_File_Created" = "true" ]; then
            echo "CSV Data Log: ✓ Created ($Statistical_Data_File)"
        else
            echo "CSV Data Log: ✓ Updated ($Statistical_Data_File)"
        fi
    else
        echo "CSV Data Log: ✗ Disabled"
    fi
    
    # SMART Test Schedule Summary
    if [[ "$Short_Test_Mode" != "3" || "$Long_Test_Mode" != "3" ]]; then
        local selftest_script="$SCRIPT_DIR/drive_selftest_omv.sh"
        if [[ -f "$selftest_script" && -x "$selftest_script" && $HAVE_ROOT == "true" ]]; then
            # Use the same logic as the detailed preview to predict next test
            local current_day=$(date +%u)  # 1=Monday, 7=Sunday
            local short_days="$Short_Drives_Tested_Days_of_the_Week"
            local long_days="$Long_Drives_Tested_Days_of_the_Week"
            local next_test_info=""
            
            # Find next short test day
            if [[ "$Short_Test_Mode" != "3" ]]; then
                for i in {0..6}; do
                    local check_day=$(( ((current_day - 1 + i) % 7) + 1 ))
                    if echo ",$short_days," | grep -q ",$check_day,"; then
                        case $check_day in
                            1) day_name="Monday" ;;
                            2) day_name="Tuesday" ;;
                            3) day_name="Wednesday" ;;
                            4) day_name="Thursday" ;;
                            5) day_name="Friday" ;;
                            6) day_name="Saturday" ;;
                            7) day_name="Sunday" ;;
                        esac
                        if [[ $i -eq 0 ]]; then
                            next_test_info="Short test today ($day_name)"
                        elif [[ $i -eq 1 ]]; then
                            next_test_info="Short test tomorrow ($day_name)"
                        else
                            next_test_info="Short test next $day_name"
                        fi
                        break
                    fi
                done
            fi
            
            # Find next long test day (only if no short test or long test is sooner)
            if [[ "$Long_Test_Mode" != "3" ]]; then
                for i in {0..6}; do
                    local check_day=$(( ((current_day - 1 + i) % 7) + 1 ))
                    if echo ",$long_days," | grep -q ",$check_day,"; then
                        case $check_day in
                            1) day_name="Monday" ;;
                            2) day_name="Tuesday" ;;
                            3) day_name="Wednesday" ;;
                            4) day_name="Thursday" ;;
                            5) day_name="Friday" ;;
                            6) day_name="Saturday" ;;
                            7) day_name="Sunday" ;;
                        esac
                        local long_test_desc=""
                        if [[ $i -eq 0 ]]; then
                            long_test_desc="Long test today ($day_name)"
                        elif [[ $i -eq 1 ]]; then
                            long_test_desc="Long test tomorrow ($day_name)"
                        else
                            long_test_desc="Long test next $day_name"
                        fi
                        
                        # Use long test if no short test scheduled or if long test is sooner
                        if [[ -z "$next_test_info" ]] || [[ $i -lt ${next_test_info_day:-8} ]]; then
                            next_test_info="$long_test_desc"
                        fi
                        break
                    fi
                done
            fi
            
            if [[ -n "$next_test_info" ]]; then
                echo "Next SMART Test: $next_test_info"
            else
                echo "SMART Tests: No tests scheduled for next 7 days"
            fi
        else
            echo "SMART Tests: Schedule unavailable (requires root or missing script)"
        fi
    else
        echo "SMART Tests: ✗ Automated testing disabled"
    fi
    
    # Log file locations
    echo ""
    echo "Log File Locations:"
    if [ -f "/tmp/multi_report_omv_errors.txt" ]; then
        echo "  Error Log: /tmp/multi_report_omv_errors.txt"
    fi
    if [ "$SDF_DataRecordEnable" = "true" ] && [ -f "$Statistical_Data_File" ]; then
        echo "  CSV Data: $Statistical_Data_File"
    fi
    if [ -n "$LOG_FILE" ] && [ -f "$LOG_FILE" ]; then
        echo "  Execution Log: $LOG_FILE"
    fi
    echo "  Standard output: Use 'journalctl -f' or check cron logs for script output"
    
    echo "================================================"
}

###### Email Functions (Based on SnapRAID Manager Email System)
###### Get email timestamp
get_email_timestamp() {
    date -R
}

###### Generate unique message ID
generate_message_id() {
    echo "<$(date +%s).$$@$(hostname)>"
}

###### Validate email configuration
validate_email_config() {
    if [ "$Email_Enable" != "true" ]; then
        return 0
    fi
    
    local valid=true
    
    # Required settings
    if [ -z "$Email_To" ]; then
        echo "Email_To is not set but email notifications are enabled"
        valid=false
    fi
    
    # Check mail command availability
    if ! command -v mail >/dev/null 2>&1; then
        echo "Mail command not found - install mailutils package"
        valid=false
    fi
    
    if [ "$valid" = "false" ]; then
        echo "Email configuration is incomplete"
        return 1
    fi
    
    return 0
}

###### Create email headers
create_email_headers() {
    local to="$1"
    local from="$2"
    local subject="$3"
    local content_type
    if [ "$Email_Use_HTML" = "true" ]; then
        content_type="text/html; charset=UTF-8"
    else
        content_type="text/plain; charset=UTF-8"
    fi
    local message_id=$(generate_message_id)
    local date=$(get_email_timestamp)
    echo "From: $from"
    echo "To: $to"
    echo "Subject: $subject"
    echo "Date: $date"
    echo "Message-ID: $message_id"
    echo "MIME-Version: 1.0"
    echo "Content-Type: $content_type"
    echo "X-Mailer: Multi-Report OMV Fork v1.2"
    echo
}

###### Send email using system mail command
send_mail_transport() {
    local email_content="$1"
    local to="$2"
    local attach_file="$3"
    local subject="$4"
    local mode="${5:-plain}"
    echo "Sending email using mail transport to: $to"
    local temp_body=$(mktemp)
    local mail_args=""
    if [ "$mode" = "html" ]; then
        printf "%s" "$email_content" > "$temp_body"
        mail_args="-s \"$subject\" -a 'Content-Type: text/html; charset=UTF-8'"
    else
        # For plain, extract subject and body
        subject=$(echo "$email_content" | grep -m 1 "^Subject: " | sed 's/^Subject: //')
        echo "$email_content" | awk '/^$/{p=1;next} p{print}' > "$temp_body"
        mail_args="-s \"$subject\" -a 'Content-Type: text/plain; charset=UTF-8'"
    fi
    if [ -n "$attach_file" ] && [ -f "$attach_file" ]; then
        echo "Attaching file: $attach_file"
        mail_args="$mail_args -A \"$attach_file\""
    fi
    # shellcheck disable=SC2086
    eval mail $mail_args "$to" < "$temp_body"
    local result=$?
    rm -f "$temp_body"
    # Report results
    if [ $result -eq 0 ]; then
        echo "Email sent successfully via transport"
        return 0
    else
        echo "Email transport failed with return code: $result"
        return $result
    fi
}

###### Main email sending function
send_email() {
    local subject="$1"
    local message="$2"
    local attach_log="${3:-false}"
    
    echo "Sending email notification"
    
    # Check if email notifications are enabled
    if [ "$Email_Enable" != "true" ]; then
        echo "Email notifications are disabled"
        return 0
    fi
    
    # Validate email configuration
    if ! validate_email_config; then
        echo "Email settings are incomplete"
        return 1
    fi
    
    # Get email settings
    local email_to="$Email_To"
    local email_from="$Email_From"
    if [ -z "$email_from" ]; then
        email_from="multi-report@$(hostname)"
    fi
    
    # Build full subject with prefix and hostname
    local full_subject="$Email_Subject_Prefix"
    if [ "$Email_Include_Hostname" = "true" ]; then
        full_subject="$full_subject [$(hostname)]"
    fi
    full_subject="$full_subject $subject"
    
    # Prepare email body and headers
    local email_body=""
    local email_headers=""
    if [ "$Email_Use_HTML" = "true" ]; then
        # Only the body, with <br> for newlines
        email_body=$(printf "%s" "$message" | sed ':a;N;$!ba;s/\n/<br>\n/g')
    else
        # For plain text, include headers in the body
        email_headers=$(create_email_headers "$email_to" "$email_from" "$full_subject")
        email_body="$email_headers$message"
    fi
    
    # Determine attachments
    local attachments=""
    
    # Add log file if requested
    if [ "$attach_log" = "true" ] && [ "$Email_Attach_Logs" = "true" ] && [ -n "$LOG_FILE" ] && [ -f "$LOG_FILE" ]; then
        attachments="$LOG_FILE"
        echo "Attaching log file: $LOG_FILE"
    fi
    
    # Add CSV file if requested
    if [ "$Email_Attach_CSV" = "true" ] && [ "$SDF_DataRecordEnable" = "true" ] && [ -f "$Statistical_Data_File" ]; then
        if [ -n "$attachments" ]; then
            attachments="$attachments,$Statistical_Data_File"
        else
            attachments="$Statistical_Data_File"
        fi
        echo "Attaching CSV file: $Statistical_Data_File"
    fi
    
    # Send email using mail transport
    if [ "$Email_Use_HTML" = "true" ]; then
        send_mail_transport "$email_body" "$email_to" "$attachments" "$full_subject" "html"
    else
        send_mail_transport "$email_body" "$email_to" "$attachments" "" "plain"
    fi
    local result=$?
    
    # Report results
    if [ $result -eq 0 ]; then
        echo "Email sent successfully"
        return 0
    else
        echo "Failed to send email, return code: $result"
        return $result
    fi
}

###### Determine if email should be sent based on results
should_send_email() {
    local has_critical="$1"
    local has_warnings="$2"
    
    case "$Email_Level" in
        "always")
            return 0  # Always send
            ;;
        "issues")
            if [ "$has_critical" = true ] || [ "$has_warnings" = true ]; then
                return 0  # Send on any issues
            fi
            ;;
        "errors")
            if [ "$has_critical" = true ]; then
                return 0  # Send only on critical errors
            fi
            ;;
        "never")
            return 1  # Never send
            ;;
    esac
    
    return 1  # Default to not sending
}

###### Automated SMART Testing Integration
run_automated_smart_testing() {
    echo "=== Automated SMART Testing ==="
    
    # Check if automated SMART testing is enabled
    if [[ "$Short_Test_Mode" == "3" && "$Long_Test_Mode" == "3" ]]; then
        echo "Automated SMART testing is disabled (both test modes set to 3)"
        echo "Configure tests via OMV Web Interface or enable in config file"
        return 0
    fi
    
    # Check if drive_selftest_omv.sh exists
    local selftest_script="$SCRIPT_DIR/drive_selftest_omv.sh"
    if [[ ! -f "$selftest_script" ]]; then
        echo "drive_selftest_omv.sh not found at: $selftest_script"
        echo "Automated SMART testing skipped"
        return 0
    fi
    
    # Check if script is executable
    if [[ ! -x "$selftest_script" ]]; then
        echo "Making drive_selftest_omv.sh executable..."
        chmod +x "$selftest_script"
    fi
    
    echo "Running automated SMART testing..."
    echo "Script: $selftest_script"
    echo ""
    
    # First, show the schedule preview using config analysis only (no actual script execution)
    echo "📅 SMART Test Schedule Preview:"
    echo "────────────────────────────────────────"
    
    # Check if we have root privileges for schedule analysis
    if [[ "$HAVE_ROOT" == "true" ]]; then
        # Show basic schedule info from config without running the selftest script
        echo "📊 Current Test Configuration:"
        local current_day=$(date +%u)  # 1=Monday, 7=Sunday
        local short_days="$Short_Drives_Tested_Days_of_the_Week"
        local long_days="$Long_Drives_Tested_Days_of_the_Week"
        
        echo "   Today: $(date '+%A, %B %d, %Y') (Day $current_day of week)"
        
        # Short test analysis
        if [[ "$Short_Test_Mode" != "3" ]]; then
            echo "   Short Tests: Enabled (Mode $Short_Test_Mode)"
            echo "     - Test $Short_Drives_to_Test_Per_Day drive(s) per day"
            echo "     - Period: Every $Short_Drives_Test_Period day(s)"
            echo "     - Active Days: $short_days"
            if echo ",$short_days," | grep -q ",$current_day,"; then
                echo "     - Today: ✅ Short tests allowed"
            else
                echo "     - Today: ⏸️  Short tests not scheduled"
            fi
        else
            echo "   Short Tests: ❌ Disabled (Mode 3)"
        fi
        
        # Long test analysis  
        if [[ "$Long_Test_Mode" != "3" ]]; then
            echo "   Long Tests: Enabled (Mode $Long_Test_Mode)"
            echo "     - Test $Long_Drives_to_Test_Per_Day drive(s) per day"
            echo "     - Period: Every $Long_Drives_Test_Period day(s)"
            echo "     - Active Days: $long_days"
            if echo ",$long_days," | grep -q ",$current_day,"; then
                echo "     - Today: ✅ Long tests allowed"
            else
                echo "     - Today: ⏸️  Long tests not scheduled"
            fi
        else
            echo "   Long Tests: ❌ Disabled (Mode 3)"
        fi
        
        echo ""
        echo "🔍 Next Test Prediction:"
        
        # Predict when next tests might run
        local next_short_day=""
        local next_long_day=""
        
        # Find next short test day
        if [[ "$Short_Test_Mode" != "3" ]]; then
            for i in {0..6}; do
                local check_day=$(( ((current_day - 1 + i) % 7) + 1 ))
                
                if echo ",$short_days," | grep -q ",$check_day,"; then
                    case $check_day in
                        1) next_short_day="Monday" ;;
                        2) next_short_day="Tuesday" ;;
                        3) next_short_day="Wednesday" ;;
                        4) next_short_day="Thursday" ;;
                        5) next_short_day="Friday" ;;
                        6) next_short_day="Saturday" ;;
                        7) next_short_day="Sunday" ;;
                    esac
                    if [[ $i -eq 0 ]]; then
                        next_short_day="Today ($next_short_day)"
                    elif [[ $i -eq 1 ]]; then
                        next_short_day="Tomorrow ($next_short_day)"
                    else
                        next_short_day="Next $next_short_day"
                    fi
                    break
                fi
            done
        fi
        
        # Find next long test day
        if [[ "$Long_Test_Mode" != "3" ]]; then
            for i in {0..6}; do
                local check_day=$(( ((current_day - 1 + i) % 7) + 1 ))
                
                if echo ",$long_days," | grep -q ",$check_day,"; then
                    case $check_day in
                        1) next_long_day="Monday" ;;
                        2) next_long_day="Tuesday" ;;
                        3) next_long_day="Wednesday" ;;
                        4) next_long_day="Thursday" ;;
                        5) next_long_day="Friday" ;;
                        6) next_long_day="Saturday" ;;
                        7) next_long_day="Sunday" ;;
                    esac
                    if [[ $i -eq 0 ]]; then
                        next_long_day="Today ($next_long_day)"
                    elif [[ $i -eq 1 ]]; then
                        next_long_day="Tomorrow ($next_long_day)"
                    else
                        next_long_day="Next $next_long_day"
                    fi
                    break
                fi
            done
        fi
        
        if [[ -n "$next_short_day" ]]; then
            echo "   🔸 Next Short Test: $next_short_day"
            echo "     Will test $Short_Drives_to_Test_Per_Day drive(s), sorted by $Short_SMART_Testing_Order"
            echo "     Note: Actual testing depends on drive rotation schedule"
        fi
        
        if [[ -n "$next_long_day" ]]; then
            echo "   🔹 Next Long Test: $next_long_day"
            echo "     Will test $Long_Drives_to_Test_Per_Day drive(s), sorted by $Long_SMART_Testing_Order"
            echo "     Note: Actual testing depends on drive rotation schedule"
        fi
        
        if [[ -z "$next_short_day" && -z "$next_long_day" ]]; then
            echo "   ⏸️  No tests scheduled (all testing disabled)"
        fi
        
        # Add debugging information to help understand why actual tests might not run
        echo ""
        echo "🔧 Debug Information:"
        echo "   Current day calculation: Today = $current_day ($(date '+%A'))"
        echo "   Short test days configured: '$short_days'"
        echo "   Long test days configured: '$long_days'"
        echo "   Short test check: Day $current_day in '$short_days'?"
        if echo ",$short_days," | grep -q ",$current_day,"; then
            echo "     ✅ YES - Short tests should be possible today"
        else
            echo "     ❌ NO - Short tests not scheduled for today"
        fi
        echo "   Long test check: Day $current_day in '$long_days'?"
        if echo ",$long_days," | grep -q ",$current_day,"; then
            echo "     ✅ YES - Long tests should be possible today"
        else
            echo "     ❌ NO - Long tests not scheduled for today"
        fi
        
        # Schedule analysis based on configuration only (no script execution)
        echo ""
        echo "🔍 Schedule Analysis (Config-Based):"
        echo "   Using configuration analysis to predict drive rotation behavior..."
        echo ""
        echo "   Drive rotation logic:"
        echo "     • Short tests use '$Short_SMART_Testing_Order' sorting"
        echo "     • Long tests use '$Long_SMART_Testing_Order' sorting"  
        echo "     • Tests rotate through drives to prevent system overload"
        echo "     • Not all drives test on every valid day (this is normal)"
        
        echo ""
        echo "   EXPLANATION: The selftest script uses period-based rotation:"
        echo "   • Short tests (Week mode): Rotates through drives every 7 days"
        echo "   • Long tests (Quarter mode): Rotates through drives every 90 days"
        echo "   • Even on valid test days, specific drives may not be 'due' for testing"
        echo "   • This is NORMAL behavior - the script spaces out testing to avoid overload"
        
        echo ""
        echo "📋 Summary:"
        
        # Determine if today is a test day
        local is_test_day=false
        local current_day_name=$(date '+%A')
        
        # Check if today is a short test day OR long test day
        if echo ",$short_days," | grep -q ",$current_day," || echo ",$long_days," | grep -q ",$current_day,"; then
            is_test_day=true
        fi
        
        if [[ "$is_test_day" == true ]]; then
            echo "   • Today ($current_day_name) IS a configured test day"
            echo "   • Actual drive testing depends on rotation schedule"
            echo ""
            echo "💡 This is NORMAL for period-based test modes:"
            echo "   • In 'Weekly' or 'Period' mode, drives rotate on a schedule"
            echo "   • Not all drives test on every valid day"
            echo "   • This prevents overwhelming the system with simultaneous tests"
            echo "   • Different drives will test on different valid days"
            echo ""
            echo "   If you want tests to run every valid day, consider switching to"
            echo "   'All Drives' mode in the selftest configuration."
        else
            echo "   • Today ($current_day_name) is NOT a configured test day"
            echo "   • NO TESTS are scheduled (as expected)"
        fi
        
        echo ""
        echo "   NOTE: If selftest script shows 'NO TESTS TO RUN' despite this prediction,"
        echo "         check the selftest script's internal logic for additional conditions"
        echo "         (drive rotation, test periods, drive availability, etc.)"
        
        echo ""
        echo "💡 To see detailed drive selection logic, run:"
        echo "   sudo bash drive_selftest_omv.sh -debug"
        
    else
        echo "⚠️  Root privileges required to check test schedule"
    fi
    echo "────────────────────────────────────────"
    echo ""
    
    # Now run the actual selftest script
    echo "🔧 Executing SMART Tests:"
    if [[ $HAVE_ROOT == "true" ]]; then
        # Run with proper logging
        if [[ "$Debug" == "true" ]]; then
            "$selftest_script" -debug
        else
            "$selftest_script"
        fi
    else
        echo "⚠️  Root privileges required for SMART testing"
        echo "Run as root or configure sudo access for smartctl commands"
        return 1
    fi
    
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        echo "✅ Automated SMART testing completed successfully"
    else
        echo "⚠️  Automated SMART testing completed with warnings (exit code: $exit_code)"
    fi
    
    return $exit_code
}

###### SMR Drive Detection Function
check_for_smr() {
    local serial="$1"
    local model="$2"
    
    # If SMR script is available, use it
    if [ -f "$SCRIPT_DIR/smr-check-omv.sh" ]; then
        # Get list of SMR drives from the SMR script
        local smr_output
        smr_output=$(bash "$SCRIPT_DIR/smr-check-omv.sh" 2>/dev/null)
        
        # Only check for serial numbers in the SMR detection table (after the separator line)
        # Look for the table section that starts after "Known SMR drive(s) detected."
        if echo "$smr_output" | grep -q "Known SMR drive(s) detected"; then
            # Extract only the table portion and check if serial appears there
            local smr_table
            smr_table=$(echo "$smr_output" | sed -n '/Known SMR drive(s) detected/,$p' | tail -n +3)
            if echo "$smr_table" | grep -q "$serial"; then
                return 0  # SMR detected in table
            else
                return 1  # Not in SMR table
            fi
        else
            return 1  # No SMR drives detected message, so no SMR
        fi
    else
        # Fallback: Basic pattern matching for known SMR drives
        # This is a simplified check - for full functionality, use smr-check-omv.sh
        case "$model" in
            # Seagate Archive series
            *"ST8000AS"*|*"ST6000AS"*|*"ST5000AS"*|*"ST4000AS"*|*"ST3000AS"*|*"ST2000AS"*)
                return 0  # Seagate Archive SMR
                ;;
            # WD Blue SMR models
            *"WD60EZAZ"*|*"WD40EZAZ"*|*"WD30EZAZ"*|*"WD20EZAZ"*)
                return 0  # WD Blue SMR
                ;;
            # Seagate Barracuda known SMR models
            *"ST2000DM008"*|*"ST2000DM005"*|*"ST3000DM007"*|*"ST4000DM004"*|*"ST5000DM000"*|*"ST6000DM003"*)
                return 0  # Seagate Barracuda SMR
                ;;
            *)
                return 1  # Assume CMR
                ;;
        esac
    fi
}

###### Main Function
main() {
    # Handle command line arguments
    if [[ "$1" == "--test-email" ]]; then
        echo "Multi-Report OMV Fork - Email Test Mode"
        echo "Date: $(date)"
        echo ""
        
        # Load configuration
        load_config
        echo ""
        
        # Test email functionality
        echo "Testing email configuration..."
        echo "Email enabled: $Email_Enable"
        echo "Email to: $Email_To"
        echo "Email level: $Email_Level"
        echo ""
        
        if [ "$Email_Enable" != "true" ]; then
            echo "❌ Email notifications are disabled in configuration"
            echo "Set Email_Enable=\"true\" in $Config_File_Name"
            exit 1
        fi
        
        if [ -z "$Email_To" ]; then
            echo "❌ Email_To is not configured"
            echo "Set Email_To=\"your-email@example.com\" in $Config_File_Name"
            exit 1
        fi
        
        # Send test email
        echo "Sending test email to: $Email_To"
        local test_message="This is a test email from Multi-Report OMV Fork.

System: $(hostname)
Date: $(date)
Configuration: $Config_File_Name

If you received this email, your email configuration is working correctly!

Email Settings:
- Recipient: $Email_To
- Sender: ${Email_From:-multi-report@$(hostname)}
- Subject Prefix: $Email_Subject_Prefix
- Include Hostname: $Email_Include_Hostname
- HTML Format: $Email_Use_HTML
- Attach Logs: $Email_Attach_Logs
- Attach CSV: $Email_Attach_CSV
- Email Level: $Email_Level

This test was generated by Multi-Report OMV Fork v1.2"
        
        if send_email "Test Email - Configuration Verification" "$test_message" "false"; then
            echo "✅ Test email sent successfully!"
            echo "Check your email inbox for the test message."
        else
            echo "❌ Failed to send test email"
            echo "Check your email configuration and system mail setup."
            echo ""
            echo "Common issues:"
            echo "- mailutils package not installed (run: sudo apt install mailutils)"
            echo "- System mail not configured"
            echo "- Invalid email address"
            echo "- Network/firewall issues"
        fi
        exit 0
    fi
    
    if [[ "$1" == "--test-smr" ]]; then
        echo "Multi-Report OMV Fork - SMR Detection Test Mode"
        echo "Date: $(date)"
        echo ""
        
        # Load configuration
        load_config
        echo ""
        
        # Run SMR test
        test_smr_detection
        exit 0
    fi
    
    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        echo "Multi-Report OMV Fork - Usage:"
        echo ""
        echo "  $0                Run normal multi-report analysis"
        echo "  $0 --test-smr     Test SMR detection functionality" 
        echo "  $0 --test-email   Test email notification configuration"
        echo "  $0 --help         Show this help message"
        echo ""
        echo "Configuration file: $Config_File_Name"
        echo ""
        echo "Email configuration requirements:"
        echo "  - Set Email_Enable=\"true\""
        echo "  - Set Email_To=\"your-email@example.com\""
        echo "  - Install mailutils: sudo apt install mailutils"
        echo "  - Configure system mail (postfix/exim4)"
        exit 0
    fi
    
    echo "Multi-Report OMV Fork Starting..."
    echo "Date: $(date)"
    echo ""
    
    # Load configuration
    load_config
    echo ""
    
    # Check root privileges
    check_root_privileges
    echo ""
    
    # System detection
    detect_omv_system
    echo ""
    
    # System information
    echo "=== System Information ==="
    get_omv_system_info
    echo ""
    
    # OMV configuration status
    get_omv_config_info
    echo ""
    
    # Drive information
    get_omv_drives
    echo ""
    
    # Initialize CSV file for statistical data
    initialize_csv_file
    echo ""
    
    # SMART data analysis
    get_smart_data
    smart_exit_code=$?
    echo ""
    
    # Optional automated SMART testing
    run_automated_smart_testing
    echo ""
    
    # Filesystem status
    get_filesystem_status
    echo ""
    
    # Generate summary report
    generate_summary_report
    
    # Determine if we have critical issues or warnings based on SMART exit code
    local has_critical=false
    local has_warnings=false
    local email_subject=""
    local email_priority="normal"
    
    case $smart_exit_code in
        2)
            has_critical=true
            email_subject="CRITICAL: Drive Issues Detected"
            email_priority="critical"
            ;;
        1)
            has_warnings=true
            email_subject="WARNING: Drive Issues Detected"
            email_priority="warning"
            ;;
        0)
            email_subject="System Status Report - All Drives Healthy"
            email_priority="normal"
            ;;
        *)
            has_warnings=true
            email_subject="System Status Report - Analysis Incomplete"
            email_priority="warning"
            ;;
    esac
    
    # Prepare email content by capturing recent output
    local email_content=""
    if should_send_email "$has_critical" "$has_warnings"; then
        echo ""
        echo "Preparing email notification..."
        
        # Build concise, actionable email content
        email_content="Multi-Report OMV Fork - Drive Health Summary
Generated: $(date)
System: $(hostname) | OMV Version: $OMV_VERSION

"
        
        # System Status Summary
        email_content+="═══ SYSTEM STATUS ═══
"
        local drive_count=$(lsblk -dn -o NAME | grep -E '^sd[a-z]+$|^nvme[0-9]+n[0-9]+$' | wc -l)
        local warning_fs=$(df -h | grep -E '^/dev/' | awk '{print $5}' | sed 's/%//' | awk '$1 >= 85' | wc -l)
        
        # Overall status
        if [ "$has_critical" = true ]; then
            email_content+="🚨 CRITICAL: Immediate attention required
"
        elif [ "$has_warnings" = true ]; then
            email_content+="⚠️  WARNING: Monitoring recommended
"
        else
            email_content+="✅ HEALTHY: All systems operating normally
"
        fi
        
        email_content+="Drives Monitored: $drive_count total
"
        
        # Filesystem warnings
        if [ "$warning_fs" -gt 0 ]; then
            email_content+="Filesystem Usage: $warning_fs warning(s)
"
        else
            email_content+="Filesystem Usage: Normal
"
        fi
        
        # OMV Service status
        if systemctl is-active --quiet openmediavault-engined; then
            email_content+="OMV Services: Running
"
        else
            email_content+="OMV Services: ⚠️ Issue detected
"
        fi
        
        # Only show drives with issues (critical or warning)
        local drives_with_issues=()
        local issue_count=0
        
        for drive in $(lsblk -dn -o NAME | grep -E '^sd[a-z]+$|^nvme[0-9]+n[0-9]+$'); do
            model=$(smartctl -i /dev/$drive 2>/dev/null | grep "Device Model\|Model Number" | cut -d: -f2 | xargs)
            serial=$(smartctl -i /dev/$drive 2>/dev/null | grep "Serial Number" | cut -d: -f2 | xargs)
            smart_status=$(smartctl -H /dev/$drive 2>/dev/null | grep "SMART overall-health\|SMART Health Status" | cut -d: -f2 | xargs)
            temp=$(smartctl -A /dev/$drive 2>/dev/null | grep -i "temperature" | head -1 | awk '{print $10}' | cut -d'(' -f1)
            
            # Get critical SMART attributes
            smart_attrs=$(smartctl -A /dev/$drive 2>/dev/null)
            reallocated=$(echo "$smart_attrs" | grep "Reallocated_Sector_Ct" | awk '{print $10}')
            pending=$(echo "$smart_attrs" | grep "Current_Pending_Sector" | awk '{print $10}')
            uncorrectable=$(echo "$smart_attrs" | grep "Offline_Uncorrectable" | awk '{print $10}')
            
            # Check if drive has any issues - using proper thresholds
            local has_issue=false
            local issues=""
            local is_critical=false
            
            # CRITICAL issues (immediate replacement required)
            if [ "$smart_status" = "FAILED" ]; then
                has_issue=true
                is_critical=true
                issues+="SMART FAILED "
            fi
            
            # Pending sectors are ALWAYS critical (drive is failing)
            if [ -n "$pending" ] && [ "$pending" -gt 0 ]; then
                has_issue=true
                is_critical=true
                issues+="PENDING (${pending}) "
            fi
            
            # Uncorrectable sectors are critical
            if [ -n "$uncorrectable" ] && [ "$uncorrectable" -gt 0 ]; then
                has_issue=true
                if [ "$uncorrectable" -gt 10 ]; then
                    is_critical=true
                    issues+="UNCORRECTABLE (${uncorrectable}) "
                else
                    issues+="UNCORRECTABLE (${uncorrectable}) "
                fi
            fi
            
            # WARNING issues (monitor closely)
            # High temperature (configurable threshold)
            if [ -n "$temp" ] && [ "$temp" -gt 50 ]; then
                has_issue=true
                if [ "$temp" -gt 60 ]; then
                    issues+="CRITICAL TEMP (${temp}°C) "
                    is_critical=true
                else
                    issues+="HIGH TEMP (${temp}°C) "
                fi
            fi
            
            # Reallocated sectors - only flag if significant (>5 for warnings, >20 for critical)
            if [ -n "$reallocated" ] && [ "$reallocated" -gt 5 ]; then
                has_issue=true
                if [ "$reallocated" -gt 20 ]; then
                    is_critical=true
                    issues+="HIGH REALLOCATED (${reallocated}) "
                else
                    issues+="REALLOCATED (${reallocated}) "
                fi
            fi
            
            # Add SMR warning if enabled
            if [ "$SMR_Enable" = "true" ] && [ -n "$serial" ] && [ "$SMR_Ignore_Alarm" != "true" ]; then
                if check_for_smr "$serial" "$model"; then
                    has_issue=true
                    issues+="SMR DRIVE "
                fi
            fi
            
            # Only include drives with actual issues
            if [ "$has_issue" = true ]; then
                if [ "$is_critical" = true ]; then
                    drives_with_issues+=("/dev/$drive:${model:-Unknown}:🚨 $issues")
                else
                    drives_with_issues+=("/dev/$drive:${model:-Unknown}:⚠️ $issues")
                fi
                issue_count=$((issue_count + 1))
            fi
        done
        
        # Show drives with issues section
        if [ ${#drives_with_issues[@]} -gt 0 ]; then
            email_content+="
═══ DRIVES REQUIRING ATTENTION ═══
"
            for drive_info in "${drives_with_issues[@]}"; do
                IFS=':' read -r drive model issues <<< "$drive_info"
                email_content+="$drive: $model
  Issues: $issues
"
            done
        else
            email_content+="
✅ All drives operating within normal parameters
"
        fi
        
        # Filesystem warnings section
        if [ "$warning_fs" -gt 0 ]; then
            email_content+="
═══ FILESYSTEM WARNINGS ═══
"
            # Get filesystem warnings properly
            local fs_warnings
            fs_warnings=$(df -h | grep -E '^/dev/' | awk '$5 ~ /%/ {usage=substr($5,1,length($5)-1); if(usage >= 85) print "⚠️ " $1 ": " $5 " used (" $4 " free)"}')
            if [ -n "$fs_warnings" ]; then
                email_content+="$fs_warnings
"
            fi
        fi
        
        # Recommendations section
        email_content+="
═══ RECOMMENDATIONS ═══
"
        
        if [ "$has_critical" = true ]; then
            email_content+="🚨 IMMEDIATE ACTION:
• Replace drives with pending sectors or SMART health FAILED status
• Backup critical data from affected drives immediately
• Stop using drives with high uncorrectable sectors (>10)
• Check system logs: journalctl -u smartd
• Consider drives with >20 reallocated sectors for replacement
"
        elif [ "$has_warnings" = true ]; then
            email_content+="⚠️ MONITOR CLOSELY:
• Track drives with elevated temperatures or reallocated sectors
• Monitor reallocated sector growth over time
• Consider replacement planning for aging drives
• Run additional SMART tests on warning drives
"
        else
            email_content+="✅ CONTINUE MONITORING:
• All drives operating normally
• Maintain regular monitoring schedule
• No immediate action required
"
        fi
        
        # Configuration summary
        email_content+="
═══ CONFIGURATION ═══
"
        if [[ "$Short_Test_Mode" != "3" || "$Long_Test_Mode" != "3" ]]; then
            email_content+="SMART Testing: Enabled (Short: $Short_Test_Mode/$Short_Drives_Test_Period, Long: $Long_Test_Mode/$Long_Drives_Test_Period)
"
            
            # Add next scheduled test information using same logic as summary
            local current_day=$(date +%u)  # 1=Monday, 7=Sunday
            local short_days="$Short_Drives_Tested_Days_of_the_Week"
            local long_days="$Long_Drives_Tested_Days_of_the_Week"
            local next_test_info=""
            
            # Find next short test day
            if [[ "$Short_Test_Mode" != "3" ]]; then
                for i in {0..6}; do
                    local check_day=$(( ((current_day - 1 + i) % 7) + 1 ))
                    if echo ",$short_days," | grep -q ",$check_day,"; then
                        case $check_day in
                            1) day_name="Monday" ;;
                            2) day_name="Tuesday" ;;
                            3) day_name="Wednesday" ;;
                            4) day_name="Thursday" ;;
                            5) day_name="Friday" ;;
                            6) day_name="Saturday" ;;
                            7) day_name="Sunday" ;;
                        esac
                        if [[ $i -eq 0 ]]; then
                            next_test_info="Short test today ($day_name)"
                        elif [[ $i -eq 1 ]]; then
                            next_test_info="Short test tomorrow ($day_name)"
                        else
                            next_test_info="Short test next $day_name"
                        fi
                        break
                    fi
                done
            fi
            
            # Find next long test day (only if no short test or long test is sooner)
            if [[ "$Long_Test_Mode" != "3" ]]; then
                for i in {0..6}; do
                    local check_day=$(( ((current_day - 1 + i) % 7) + 1 ))
                    if echo ",$long_days," | grep -q ",$check_day,"; then
                        case $check_day in
                            1) day_name="Monday" ;;
                            2) day_name="Tuesday" ;;
                            3) day_name="Wednesday" ;;
                            4) day_name="Thursday" ;;
                            5) day_name="Friday" ;;
                            6) day_name="Saturday" ;;
                            7) day_name="Sunday" ;;
                        esac
                        local long_test_desc=""
                        if [[ $i -eq 0 ]]; then
                            long_test_desc="Long test today ($day_name)"
                        elif [[ $i -eq 1 ]]; then
                            long_test_desc="Long test tomorrow ($day_name)"
                        else
                            long_test_desc="Long test next $day_name"
                        fi
                        
                        # Use long test if no short test scheduled or if long test is sooner
                        if [[ -z "$next_test_info" ]] || [[ $i -lt ${next_test_info_day:-8} ]]; then
                            next_test_info="$long_test_desc"
                        fi
                        break
                    fi
                done
            fi
            
            if [[ -n "$next_test_info" ]]; then
                email_content+="Next Test: $next_test_info
"
            else
                email_content+="Next Test: No tests scheduled for next 7 days
"
            fi
        else
            email_content+="SMART Testing: Disabled
"
        fi
        
        if [ "$SDF_DataRecordEnable" = "true" ]; then
            email_content+="CSV Logging: Enabled ($Statistical_Data_File)
"
        else
            email_content+="CSV Logging: Disabled
"
        fi
        
        email_content+="Email Level: $Email_Level | Root Access: $HAVE_ROOT

---
Multi-Report OMV Fork v1.2 | For detailed analysis, check console output
SnapRAID status available via separate SnapRAID Manager script
"
        
        # Send the email
        if send_email "$email_subject" "$email_content" "false"; then
            echo "✅ Email notification sent successfully to: $Email_To"
        else
            echo "❌ Failed to send email notification"
        fi
    else
        echo "Email notification skipped (level: $Email_Level)"
    fi
    
    if [ "$HAVE_ROOT" = true ]; then
        echo "Multi-Report OMV Fork completed successfully!"
    else
        echo "Multi-Report OMV Fork completed with limited functionality!"
        echo "Run with sudo for full SMART data access."
    fi
    echo "Note: SnapRAID status handled by separate SnapRAID manager script"
    
    # Exit with appropriate code based on SMART analysis
    exit $smart_exit_code
}

# Run main function if script is executed directly  
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
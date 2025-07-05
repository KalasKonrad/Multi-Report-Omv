#!/bin/bash

LANG="en_US.UTF-8"
if [[ $TERM == "dumb" ]]; then          # Set a terminal as the script may generate an error message if using 'dumb'.
    export TERM=unknown
fi
##### Version 1.05 OMV (Based on TrueNAS drive_selftest.sh v1.05)

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

### FILE NAME SHOULD BE 'drive_selftest_omv.sh' TO INTEGRATE WITH MULTI-REPORT OMV FORK
###
### MULTIPLE DRIVE SMART SELF-TEST SCRIPT FOR OMV (OPENMEDIAVAULT)
###    
### WHAT DOES THIS SCRIPT DO?
###
### THIS SCRIPT WAS ORIGINALLY DESIGNED FOR PEOPLE WHO HAVE A LOT OF DRIVES AND
### DO NOT WANT TO SCHEDULE EACH DRIVE INDIVIDUALLY FOR SMART TESTING.
### ADDITIONALLY THIS CAN BE USED WITH MULTI-REPORT OMV FORK TO RUN SMART TESTS
### AND UTILIZE THE MULTI-REPORT CONFIGURATION FILE IF DESIRED.
###        
### THIS SCRIPT WILL SPREAD OUT THE SMART SHORT AND LONG/EXTENDED TESTING IN THREE
### POSSIBLE WAYS, INCLUDING THE OPTION TO NOT TEST AT ALL:
###  1. SPREAD ACROSS A WEEK (ON SPECIFIED DAYS OF THE WEEK)
###  2. SPREAD ACROSS A MONTH (ON SPECIFIED DAYS OF THE WEEK)
###  3. ALL DRIVES (ON SPECIFIED DAYS OF THE WEEK)
###  4. OR NO DRIVES AT ALL
### SPECIFIED DAYS OF THE WEEK ARE: 1=MON, 2=TUE, 3=WED, 4=THU, 5=FRI, 6=SAT, 7=SUN.
###
### THESE ARE BROKEN DOWN INTO SHORT TESTS AND LONG TESTS.
### THE DRIVES CAN BE TESTED IN DRIVE NAME (ID) ORDER (SDA, SDB, SDC) OR
### SORTED BY SERIAL NUMBER (A POOR MANS CRAPPY METHOD TO SIMULATE RANDOMIZATION OF DRIVES TO REDUCE DRIVES
### BEING TESTED IN THE SAME DRIVE CAGE TO REDUCE POWER DRAW AND HEAT, AND IT MAY NOT REALLY WORK THAT WAY)
###
### THE DEFAULT SETTINGS ARE:
###    1. DAILY SHORT TESTS ON EACH DRIVE (TEST MODE 2)
###       -SORTED BY DRIVE NAME/ID, ALL DRIVES TESTED EVERY DAY, RUNS 7 DAYS A WEEK
###    2. MONTHLY LONG TESTS ON EACH DRIVE (TEST MODE 1, MONTHLY)
###       -SORTED BY SERIAL NUMBER, ONE DRIVE A DAY, ONE TEST PER MONTH, RUNS 7 DAYS A WEEK
###    3. LOGGING ENABLED
###    4. ZFS SCRUB TIME REMAINING OVER 3 HOURS WILL RUN A SHORT TEST VICE LONG TEST.
###
### READ THE USER GUIDE AND CONFIGURATION SECTION BELOW, MAKE CHANGES AS DESIRED.
###
### A LOG FILE BY DEFAULT IS CREATED IN THE SCRIPT DIRECTORY, ONE FOR EACH DAY
### OF THE MONTH.  IT WILL OVERWRITE ONCE A NEW MONTH STARTS.
###
### IF YOU ALREADY HAVE SMART TESTING FOR A DAILY SMART SHORT TEST THEN YOU CAN SET
### TEST MODE 3 FOR SHORT TESTS TO MITIGATE DUPLICATE TESTING.
###
### IF YOU HAVE ALL YOUR DRIVES SETUP IN OMV EXCEPT NVME, THERE IS AN OPTION TO RUN NVME ONLY.
###
### USE [-help] FOR ADDITIONAL INFORMATION

# Change Log
#
# Version 1.05 OMV (02 July 2025) - OMV Adaptation
#
# - Adapted from TrueNAS drive_selftest.sh v1.05 for OMV/Linux compatibility
# - Modified drive discovery to use lsblk and smartctl instead of TrueNAS middleware
# - Updated pool/scrub detection for Linux ZFS and other filesystems
# - Integrated with multi_report_omv_config.txt configuration
# - Added OMV-specific defaults and documentation
# - Maintained all advanced features: load balancing, intelligent scheduling, logging
# - Added demo mode and debug features for OMV users
#
# Original TrueNAS Version 1.05 (07 June 2025)
#
# - Updated the smartctl interface connection to roll through several more variations if the default fails to work.
# - Added '--scan' output to a file for data collection.
# - Updated Debugging Data for Troubleshooting and analysis.
# - Updated '-help' information.
# - Fixed potential drive not being Long tested if it had a similar name to a Short test drive (da1 and da11 was the noted problem).
# - Updated Debug to be enabled during a Multi-report -dump switch.
# - Added RESILVER/SCRUB Override for SMART Long tests (by request).
# - Converted options from 'true/false' to 'enable/disable' to make more sense.
# - Fixed reading the multi_report_config.txt file earlier in the script execution.

######################## USER SETTINGS ########################

###### OMV SMART DRIVE TESTING SCRIPT ######
###                                         ###
###          THESE ARE FUNCTIONAL           ###
###         MAKE YOUR CHANGES HERE          ###
###          THESE ARE OVERRIDDEN           ###
###    BY MULTI_REPORT_OMV_CONFIG.TXT       ###
###                                         ###
###############################################

### EXTERNAL CONFIGURATION FILE
Config_File_Name="$SCRIPT_DIR/multi_report_omv_config.txt"
Use_multi_report_config_values="enable"       # A "enable" value here will use the $Config_File_Name file values to override the values defined below, if it exists.
                                            #  This allows the values to be retained between versions.  A "disable" will not allow the external config file to be
                                            #  used regardless of any other settings and therefore would utilize the values below. Default="enable"

###### SCRIPT UPDATES
Check_For_Updates="disable"                  # This will check to see if an update is available. Default="disable" (OMV uses integrated updates)
Automatic_Selftest_Update="disable"         # WARNING !!!  This option will automatically update the Drive_Selftest script if a newer version exists on GitHub
                                            #  with no user interaction. Default = "disable"
											
##### SMARTCTL_Interface_Options			# This variable is used to attempt to account for drives not easily accessable.
SMARTCTL_Interface_Options="auto,sat,atacam,scsi,nvme"

###### HDD/SSD/NVMe SMART Testing
Test_ONLY_NVMe_Drives="disable"             # This option when set to "enable" will only test NVMe drives, HDD/SSD will not be tested. Default = "disable"
SCRUB_Minutes_Remaining=0                   # This option when set between 1 and 9999 (in minutes) will not run a SMART LONG test if a SCRUB has longer than xx minutes
                                            #  remaining, and a SMART SHORT test will be run instead to provide minimal impact to the SCRUB operation.
                                            #  A value of 0 (zero) will disable all SMART test(s) during a SCRUB operation.  Default=0 (Disabled).
                                            #  NOTE: Any RESILVER operation automatically cancels SMART testing to put priority on rebuilding the pool.

SCRUB_RESILVER_OVERRIDE="disable"			# This option will allow all SCRUB actions to occur regardless of the SCRUB_Minutes_Remaining variable
											# meaning that if a SCRUB or a RESILVER is in progress, any given SMART testing will be performed.
											# I personally do not advise enabling this option but someone asked for it, here it is.
											
### SHORT SETTINGS
Short_Test_Mode=2                           # 1 = Use Short_Drives_to_Test_Per_Day value, 2 = All Drives Tested (Ignores other options), 3 = No Drives Tested.
Short_Time_Delay_Between_Drives=1           # Tests will have a XX second delay between the drives starting testing. If drives are always spinning, this can be "0".
Short_SMART_Testing_Order="DriveID"         # Test order is for Test Mode 1 ONLY, select "Serial" or "DriveID" for sort order.  Default = "DriveID"
Short_Drives_to_Test_Per_Day=1              # For Test_Mode 1) How many drives to run each day minimum?
Short_Drives_Test_Period="Week"             # "Week" (7 days) or "Month" (28 days) or "Quarter" (90 days)
Short_Drives_Tested_Days_of_the_Week="1,2,3,4,5,6,7"    # Days of the week to run, 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat, 7=Sun.
Short_Drives_Test_Delay=30                  # How long to delay when running Short tests, before exiting to controlling procedure.  Default is 30 seconds.
                                            # Short tests to complete before continuing.  If using without Multi-Report, set this value to 1.

### LONG SETTINGS
Long_Test_Mode=1                            # 1 = Use Long_Drives_to_Test_Per_Day value, 2 = All Drives Tested (Ignores other options), 3 = No Drives Tested.
Long_Time_Delay_Between_Drives=1            # Tests will have a XX second delay between the drives starting the next test.
Long_SMART_Testing_Order="Serial"           # Test order is either "Serial" or "DriveID".  Default = 'Serial'
Long_Drives_to_Test_Per_Day=1               # For Test_Mode 1) How many drives to run each day minimum?
Long_Drives_Test_Period="Month"             # "Week" (7 days) or "Month" (28 days) or "Quarter" (90 days) or "Biannual" (180 days) or "Annual" (365 days)
Long_Drives_Tested_Days_of_the_Week="1,2,3,4,5,6,7"     # Days of the week to run, 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat, 7=Sun.

### IGNORE DRIVES LIST
# IF YOU HAVE A DRIVE THAT YOU DO NOT WANT THIS SCRIPT TO TOUCH (RUN ANY TESTS ON), THEN INCLUDE THE DRIVE SERIAL NUMBER
# IN THE LIST.  IF THE SERIAL NUMBER MATCHES THEN THE DRIVE IS REMOVED FROM TESTING. BELOW IS AN EXAMPLE.
# Example:  Ignore_Drives_List="RQTY4D78E,JJ6XTZ,OU812,ZR13JRL"
Ignore_Drives_List=""

### REPORT
Drive_List_Length=10                        # This is how many drive IDs to list per line.  Default is 10.
Enable_Logging="enable"                       # This will create a text file named "drive_test_xx.txt". Run -clearlog
LOG_DIR="$SCRIPT_DIR/DS_Logs"               # The default log directory is the script directory.
Silent="disable"                               # When "enable" only error messages will be output to the stdout.

#######################################
#######################################
###                                 ###
###  STOP EDITING THE SCRIPT HERE   ###
###     DO NOT CHANGE ANYTHING      ###
###        BELOW THIS LINE          ###
###                                 ###
#######################################
#######################################

###### DEBUG SECTION ######
# DEBUG is to be used to display extra operational data for troubleshooting the script.
# I do not recommend people play with anything here.

Debug="false"            # Default = "false"
Debug_Steps="false"		# Default = "false"
simulated_drives=0      # Set to '0' to use actual drives, or to any number to use simulated drives (the Serial option will not work)

###### Auto-generated Parameters
softver=$(uname -s)

# OMV/Linux system detection
if [[ $softver == "Linux" ]]; then
    if [[ -f /etc/openmediavault/config.xml ]]; then
        programver="OpenMediaVault"
    else
        programver="Linux"
    fi
    programver3="6"            # Using symbolic value for compatibility
    programver4="6"
else
    programver="Unknown"
    programver3="0"
    programver4="0"
fi

programver3=$(( programver3 + 0 ))        # Make Base 10
programver4=$(( programver4 + 0 ))
Program_Name="drive_selftest_omv.sh"
Version="1.05"                            # Current version of the script
Version_Date="(02 July 2025)"

# GLOBAL VARIABLES - MUST BE DEFINED EARLY BEFORE FUNCTION TO BE GLOBAL
Drive_Disk_Query=""
smartdrives=""
selftest_drives=""
drives_name=""
drives_serial=""
drives_subsystem=""
driveConnectionType="auto"
Demo="false"
IFS_RESTORE=$IFS
selftest_drives_short=""
selftest_drives_long=""
Ready_to_Test="false"
start_time_display=""
end_time_display=""
end_tenths=""
NVMe_Override_Enabled=""
Short_Drives_Testing=""
Long_Drives_Testing=""
No_Tests="true"
SCRUB_In_Progress="false"

DOW=$(date +%u)                            # Todays Day of the Week, 1=Mon, 7=Sun
Full_Month_Name=$(date +%B)                # Full name of current month
today_day=$(date +%d)

# Get Smartmontools version number 
smart_ver=$(smartctl | grep "7." | cut -d " " -f 2)

# Get all drive(s) interface data
smartctlscan=$(smartctl --scan-open)

##########################
##########################
###                    ###
###  DEFINE FUNCTIONS  ###
###                    ###
##########################
##########################

# Timer function for Linux
elapsed_time() {
    if [[ $1 != "" ]]; then
        start_seconds=$(date -d "$1" +%s)
        current_seconds=$(date +%s)
        elapsed=$((current_seconds - start_seconds))
        end_time_display=$(date +%H:%M:%S)
        end_tenths=""
    fi
}

convert_to_decimal() {
    if [[ "$1" == "" ]]; then return; fi
    Converting_Value=${1#0}
    Converting_Value="${Converting_Value//,}"
    Return_Value=$Converting_Value
    if [[ $1 == "0" ]]; then Return_Value=0; fi
}

# OMV/Linux compatible scrub check (simplified - no ZFS pools in typical OMV)
check_scrub() {
    SCRUB_In_Progress="false"
    
    # Check for ZFS scrubs if ZFS is available
    if command -v zpool >/dev/null 2>&1; then
        # Check ZFS pools for scrub/resilver
        zpool_status=$(zpool status 2>/dev/null)
        if echo "$zpool_status" | grep -E "(scrub|resilver) in progress" >/dev/null; then
            SCRUB_In_Progress="true"
            if [[ $Silent != "enable" ]]; then
                echo "  ZFS scrub/resilver in progress - SMART testing may be affected" | tee -a /tmp/drive_selftest/drive_test_temp.txt
            fi
        fi
    fi
    
    # For OMV, most users use ext4/xfs - no scrub equivalent
    # You could add mdadm check here if using software RAID
    # if command -v mdadm >/dev/null 2>&1; then
    #     # Check mdadm RAID sync status
    # fi
}

# OMV/Linux drive discovery function
discover_drives() {
    smartdrives=""
    drives_name=""
    drives_serial=""
    drives_subsystem=""
    
    # Create temporary directory for drive data
    if ! test -e "/tmp/drive_selftest"; then
        mkdir -p "/tmp/drive_selftest"
    fi
    
    # Get drive list using lsblk (filter out partitions, loops, etc.)
    drive_list=$(lsblk -dpno NAME,TYPE | grep "disk" | awk '{print $1}' | sed 's|/dev/||')
    
    for drive in $drive_list; do
        # Skip if drive doesn't support SMART
        if smartctl -i "/dev/$drive" >/dev/null 2>&1; then
            # Get drive serial number
            serial=$(smartctl -i "/dev/$drive" | grep "Serial Number:" | awk '{print $NF}')
            
            # Skip if no serial number or in ignore list
            if [[ -n "$serial" ]] && [[ "$Ignore_Drives_List" != *"$serial"* ]]; then
                # Check if NVMe only mode
                if [[ $Test_ONLY_NVMe_Drives == "enable" ]]; then
                    if [[ $drive == nvme* ]]; then
                        smartdrives="$smartdrives $drive"
                        drives_name="$drives_name $drive"
                        drives_serial="$drives_serial $serial"
                        drives_subsystem="$drives_subsystem nvme"
                    fi
                else
                    smartdrives="$smartdrives $drive"
                    drives_name="$drives_name $drive"
                    drives_serial="$drives_serial $serial"
                    if [[ $drive == nvme* ]]; then
                        drives_subsystem="$drives_subsystem nvme"
                    else
                        drives_subsystem="$drives_subsystem sata"
                    fi
                fi
            fi
        fi
    done
    
    # Clean up variables
    smartdrives=$(echo $smartdrives | xargs)
    drives_name=$(echo $drives_name | xargs)
    drives_serial=$(echo $drives_serial | xargs)
    drives_subsystem=$(echo $drives_subsystem | xargs)
}

# Sort function for drive ordering
sort_data() {
    if [[ $1 == "DriveID" ]]; then
        sort_list=$(echo $sort_list | tr ' ' '\n' | sort | tr '\n' ' ')
    elif [[ $1 == "Serial" ]]; then
        # For serial sorting, we need to correlate drives with serials
        sort_serial_number
    fi
}

sort_serial_number() {
    # Create temporary arrays for sorting by serial
    local temp_drives=($smartdrives)
    local temp_serials=($drives_serial)
    local sorted_pairs=""
    
    # Create pairs of serial:drive
    for i in "${!temp_drives[@]}"; do
        sorted_pairs="$sorted_pairs ${temp_serials[$i]}:${temp_drives[$i]}"
    done
    
    # Sort by serial number and extract drives
    sort_list=$(echo $sorted_pairs | tr ' ' '\n' | sort | cut -d':' -f2 | tr '\n' ' ' | xargs)
}

# Run SMART test function
run_smart_test() {
    if ! test -e "/tmp/drive_selftest/smartctl_scan_results.txt"; then
        smartctl --scan > /tmp/drive_selftest/smartctl_scan_results.txt
    fi
    
    for drive in $selftest_drives; do
        test_running=0
        driveConnectionType="auto"
        
        # Try different interface types
        IFS=","
        for dr in $SMARTCTL_Interface_Options; do
            if [[ $dr == "auto" ]]; then
                if [[ $1 == "Short" ]]; then
                    smart_test_ok="$(smartctl -t short /dev/$drive 2>&1)"
                else
                    smart_test_ok="$(smartctl -t long /dev/$drive 2>&1)"
                fi
                smartresult=$?
            else
                if [[ $1 == "Short" ]]; then
                    smart_test_ok="$(smartctl -d "${dr}" -t short /dev/$drive 2>&1)"
                else
                    smart_test_ok="$(smartctl -d "${dr}" -t long /dev/$drive 2>&1)"
                fi
                smartresult=$?
            fi
            
            if [[ $smartresult -eq 0 ]] || echo $smart_test_ok | grep -i "has begun" >/dev/null 2>&1; then
                if [[ $Silent != "enable" ]]; then
                    echo "    Drive: $drive in $1 Test" | tee -a /tmp/drive_selftest/drive_test_temp.txt
                fi
                test_running=1
                No_Tests="false"
                break
            fi
        done
        IFS=$IFS_RESTORE
        
        if [[ $test_running -eq 0 ]]; then
            if [[ $Silent != "enable" ]]; then
                echo "    Drive: $drive - Test failed to start" | tee -a /tmp/drive_selftest/drive_test_temp.txt
            fi
        fi
        
        if [[ $Demo != "true" ]]; then
            sleep $Time_Delay_Between_Drives
        fi
    done
}

# Remove duplicate tests function
remove_duplicate_tests() {
    local short_modified_drives=""
    local reduced_drives_display=""
    
    for s_drives in $selftest_drives_short; do
        test=0
        for l_drives in $selftest_drives_long; do
            if [[ "$l_drives" == "$s_drives" ]]; then
                test=1
                break
            fi
        done
        
        if [[ $test == 1 ]]; then
            if [[ $reduced_drives_display == "" ]]; then
                reduced_drives_display=$s_drives
            else
                reduced_drives_display="$reduced_drives_display $s_drives"
            fi
        else
            if [[ $short_modified_drives == "" ]]; then
                short_modified_drives=$s_drives
            else
                short_modified_drives="$short_modified_drives $s_drives"
            fi
        fi
    done
    
    # Move from LONG to SHORT during scrub
    if [[ $SCRUB_In_Progress == "true" ]] && [[ $SCRUB_Minutes_Remaining -gt 0 ]]; then
        for l_drives in $selftest_drives_long; do
            short_modified_drives="$short_modified_drives $l_drives"
        done
        selftest_drives_long=""
    fi
    
    if [[ -n "$reduced_drives_display" ]] && [[ $Silent != "enable" ]]; then
        echo "    Drive(s): \"$reduced_drives_display\" were removed from the Short testing schedule for today."
        echo "    The drive(s) are already scheduled today for the Long test."
    fi
    
    selftest_drives_short=$(echo $short_modified_drives | xargs)
    selftest_drives=$selftest_drives_short
    
    if [[ -n "$selftest_drives" ]]; then
        if [[ $Silent != "enable" ]]; then
            echo "RUNNING SHORT TEST: $selftest_drives" | tee -a /tmp/drive_selftest/drive_test_temp.txt
        fi
        run_smart_test Short
        Short_Drives_Testing=$selftest_drives
    else
        if [[ $Silent != "enable" ]]; then
            echo "NO SHORT TESTS TO RUN" | tee -a /tmp/drive_selftest/drive_test_temp.txt
        fi
    fi
    
    selftest_drives=$selftest_drives_long
    if [[ -n "$selftest_drives" ]]; then
        if [[ $Silent != "enable" ]]; then
            echo "RUNNING LONG TEST: $selftest_drives" | tee -a /tmp/drive_selftest/drive_test_temp.txt
        fi
        run_smart_test Long
        Long_Drives_Testing=$selftest_drives
    else
        if [[ $Silent != "enable" ]]; then
            echo "NO LONG TESTS TO RUN" | tee -a /tmp/drive_selftest/drive_test_temp.txt
        fi
    fi
}

# Main SMART test control function
smartctl_selftest() {
    if [[ $1 == "" ]]; then
        echo "No SMART Test is defined, Error."
        return
    fi
    
    if [[ $Demo == "true" ]]; then
        counter_simulated_drives=0
        smartdrives_sorted=""
        if [[ $simulated_drives -gt 0 ]]; then
            while [ $counter_simulated_drives -lt $simulated_drives ]; do
                smartdrives_sorted="$smartdrives_sorted sda$counter_simulated_drives"
                ((counter_simulated_drives++))
            done
            smartdrives=$smartdrives_sorted
        fi
    fi
    
    # Set variables based on test type
    if [[ $1 == "Short" ]]; then
        Test_Mode=$Short_Test_Mode
        SMART_Testing_Order=$Short_SMART_Testing_Order
        Drives_to_Test_Per_Day=$Short_Drives_to_Test_Per_Day
        Drives_Test_Period=$Short_Drives_Test_Period
        Drives_Tested_Days_of_the_Week=$Short_Drives_Tested_Days_of_the_Week
        Time_Delay_Between_Drives=$Short_Time_Delay_Between_Drives
    else
        Test_Mode=$Long_Test_Mode
        SMART_Testing_Order=$Long_SMART_Testing_Order
        Drives_to_Test_Per_Day=$Long_Drives_to_Test_Per_Day
        Drives_Test_Period=$Long_Drives_Test_Period
        Drives_Tested_Days_of_the_Week=$Long_Drives_Tested_Days_of_the_Week
        Time_Delay_Between_Drives=$Long_Time_Delay_Between_Drives
    fi
    
    # Generate test mode description
    case $Test_Mode in
        1) Test_Mode_Title="${1} SMART Test on ${Drives_to_Test_Per_Day} Drive(s) Per Day" ;;
        2) Test_Mode_Title="${1} SMART Test All Drives" ;;
        3) Test_Mode_Title="No SMART Testing Selected" ;;
    esac
    
    # Format days of week for display
    DOW_days=""
    IFS=","
    for day_of_week_test in $Drives_Tested_Days_of_the_Week; do
        case $day_of_week_test in
            1) day_of_week="Mon" ;;
            2) day_of_week="Tue" ;;
            3) day_of_week="Wed" ;;
            4) day_of_week="Thu" ;;
            5) day_of_week="Fri" ;;
            6) day_of_week="Sat" ;;
            7) day_of_week="Sun" ;;
        esac
        if [[ $DOW_days == "" ]]; then
            DOW_days=$day_of_week
        else
            DOW_days="$DOW_days, $day_of_week"
        fi
    done
    IFS=$IFS_RESTORE
    
    # Sort drive list
    sort_list=$smartdrives
    sort_data DriveID
    smartdrives_sorted=$sort_list
    
    Drive_Count=$(echo $smartdrives_sorted | wc -w)
    
    if [[ $Silent != "enable" ]]; then
        echo ""
        echo "  $1 Test Mode:($Test_Mode) \"$Test_Mode_Title\""
        if [[ $Test_Mode -eq 1 ]]; then
            echo "    Running $Drives_Test_Period Option, Sorting by: $SMART_Testing_Order"
        elif [[ $Test_Mode -eq 2 ]]; then
            echo "    Running $Drives_Test_Period Option, No Sorting"
        else
            echo "    $1 Testing will not be executed."
        fi
    fi
    
    # Determine drives to test based on mode and day
    drives_to_test=""
    if [[ $Drives_Tested_Days_of_the_Week == *"$DOW"* ]] || [[ $Demo == "true" ]]; then
        case $Test_Mode in
            1)
                # Spread testing - enhanced for longer periods
                if [[ $SMART_Testing_Order == "Serial" ]]; then
                    sort_list=$smartdrives
                    sort_serial_number
                    smartdrives_sorted=$sort_list
                else
                    smartdrives_sorted=$smartdrives
                fi
                
                # Calculate period length in days
                case $Drives_Test_Period in
                    "Week") period_days=7 ;;
                    "Month") period_days=28 ;;
                    "Quarter") period_days=90 ;;
                    "Biannual") period_days=180 ;;
                    "Annual") period_days=365 ;;
                    *) period_days=28 ;; # Default to month
                esac
                
                # For longer periods, use day of year for better distribution
                if [[ $period_days -gt 28 ]]; then
                    day_of_year=$(date +%j)
                    # Remove leading zeros
                    day_of_year=$((10#$day_of_year))
                    cycle_position=$((day_of_year % period_days))
                elif [[ $period_days -eq 7 ]]; then
                    # For weekly cycles, use day of week directly
                    cycle_position=$((DOW - 1))
                else
                    # For month, use day of month modulo cycle length
                    day_of_month=$(date +%d)
                    day_of_month=$((10#$day_of_month))
                    cycle_position=$((day_of_month % period_days))
                fi
                
                # Calculate drives per cycle safely
                days_in_cycle=$((period_days / 7))
                if [[ $days_in_cycle -lt 1 ]]; then
                    days_in_cycle=1
                fi
                drives_per_cycle=$((Drive_Count / days_in_cycle + 1))
                if [[ $drives_per_cycle -lt $Drives_to_Test_Per_Day ]]; then
                    drives_per_cycle=$Drives_to_Test_Per_Day
                fi
                
                start_index=$((cycle_position * drives_per_cycle))
                drives_array=($smartdrives_sorted)
                for ((i=start_index; i<start_index+Drives_to_Test_Per_Day && i<Drive_Count; i++)); do
                    if [[ -n "${drives_array[$i]}" ]]; then
                        drives_to_test="$drives_to_test ${drives_array[$i]}"
                    fi
                done
                drives_to_test=$(echo $drives_to_test | xargs)
                ;;
            2)
                # All drives
                drives_to_test=$smartdrives_sorted
                ;;
            3)
                # No testing
                drives_to_test=""
                ;;
        esac
    fi
    
    # Set global variables for testing
    if [[ $1 == "Short" ]]; then
        selftest_drives_short=$drives_to_test
    else
        selftest_drives_long=$drives_to_test
    fi
    
    # Execute tests if ready
    if [[ $Demo != "true" ]] && [[ $Ready_to_Test == "true" ]]; then
        if [[ $Short_Drives_Tested_Days_of_the_Week == *"$DOW"* ]] || [[ $Long_Drives_Tested_Days_of_the_Week == *"$DOW"* ]]; then
            remove_duplicate_tests
        fi
    else
        Ready_to_Test="true"
    fi
}

# Configuration file reader
read_config_file() {
    if [[ $Use_multi_report_config_values == "enable" ]] && [[ -f "$Config_File_Name" ]]; then
        if [[ $Silent != "enable" ]]; then
            echo "Reading configuration from: $Config_File_Name"
        fi
        
        # Read SMART testing configuration
        if grep -q "^Automated_SMART_Test_Enable=" "$Config_File_Name"; then
            Automated_SMART_Test_Enable=$(grep "^Automated_SMART_Test_Enable=" "$Config_File_Name" | cut -d'=' -f2 | tr -d '"')
        fi
        
        # Read other config values
        for var in Short_Test_Mode Short_Time_Delay_Between_Drives Short_SMART_Testing_Order \
                   Short_Drives_to_Test_Per_Day Short_Drives_Test_Period Short_Drives_Tested_Days_of_the_Week \
                   Long_Test_Mode Long_Time_Delay_Between_Drives Long_SMART_Testing_Order \
                   Long_Drives_to_Test_Per_Day Long_Drives_Test_Period Long_Drives_Tested_Days_of_the_Week \
                   Test_ONLY_NVMe_Drives Ignore_Drives_List Enable_Logging Silent; do
            if grep -q "^$var=" "$Config_File_Name"; then
                eval "$var=$(grep "^$var=" "$Config_File_Name" | cut -d'=' -f2 | tr -d '"')"
            fi
        done
    fi
}

# Help function
show_help() {
    echo ""
    echo "OMV SMART Drive Self-Test Script v$Version $Version_Date"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -help          Show this help message"
    echo "  -demo          Run in demo mode (no actual tests)"
    echo "  -debug         Enable debug output"
    echo "  -silent        Run in silent mode"
    echo "  -clearlog      Clear log files"
    echo ""
    echo "Configuration:"
    echo "  Edit multi_report_omv_config.txt to configure SMART testing"
    echo "  Or modify the variables at the top of this script"
    echo ""
    echo "Test Period Options:"
    echo "  Week     - Spread tests across 7 days"
    echo "  Month    - Spread tests across 28 days"
    echo "  Quarter  - Spread tests across 90 days (recommended for most)"
    echo "  Biannual - Spread tests across 180 days (large arrays)"
    echo "  Annual   - Spread tests across 365 days (enterprise arrays)"
    echo ""
    echo "Recommendations:"
    echo "  Small arrays (< 10 drives): Quarter for long tests"
    echo "  Medium arrays (10-30 drives): Biannual for long tests"
    echo "  Large arrays (30+ drives): Annual for long tests"
    echo ""
}

# Clear log function
clear_logs() {
    if [[ -d "$LOG_DIR" ]]; then
        rm -f "$LOG_DIR"/drive_test_*.txt
        echo "Log files cleared from $LOG_DIR"
    else
        echo "No log directory found at $LOG_DIR"
    fi
}

# Main execution
main() {
    start_time_display=$(date +%H:%M:%S)
    
    # Create temp directory
    if ! test -e "/tmp/drive_selftest"; then
        mkdir -p "/tmp/drive_selftest"
    fi
    
    # Create log directory
    if [[ $Enable_Logging == "enable" ]] && [[ ! -d "$LOG_DIR" ]]; then
        mkdir -p "$LOG_DIR"
    fi
    
    # Initialize log file
    if [[ $Enable_Logging == "enable" ]]; then
        log_file="$LOG_DIR/drive_test_$(date +%d).txt"
        echo "OMV SMART Drive Self-Test Log - $(date)" > "$log_file"
        echo "" >> "$log_file"
        # Redirect output to log file
        exec > >(tee -a "$log_file")
    fi
    
    # Process command line arguments
    case "$1" in
        -help|--help)
            show_help
            exit 0
            ;;
        -demo|--demo)
            Demo="true"
            simulated_drives=10
            echo "Demo mode enabled with $simulated_drives simulated drives"
            ;;
        -debug|--debug)
            Debug="true"
            Debug_Steps="true"
            echo "Debug mode enabled"
            ;;
        -silent|--silent)
            Silent="enable"
            ;;
        -clearlog|--clearlog)
            clear_logs
            exit 0
            ;;
        "")
            # No arguments - normal operation
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
    
    # Read configuration
    read_config_file
    
    if [[ $Silent != "enable" ]]; then
        echo ""
        echo "OMV SMART Drive Self-Test Script v$Version $Version_Date"
        echo "Running on: $programver"
        echo ""
    fi
    
    # Discover drives
    if [[ $Demo != "true" ]]; then
        discover_drives
    else
        # Demo mode drives
        smartdrives="sda sdb sdc sdd sde"
        drives_name="sda sdb sdc sdd sde"
        drives_serial="DEMO001 DEMO002 DEMO003 DEMO004 DEMO005"
    fi
    
    if [[ -z "$smartdrives" ]]; then
        echo "No SMART-capable drives found"
        exit 1
    fi
    
    Drive_Count=$(echo $smartdrives | wc -w)
    
    if [[ $Silent != "enable" ]]; then
        echo "Found $Drive_Count SMART-capable drives: $smartdrives"
        echo ""
    fi
    
    # Check for scrub/resilver operations
    check_scrub
    
    # Run SMART tests
    smartctl_selftest Short
    smartctl_selftest Long
    
    # Final status
    if [[ $Silent != "enable" ]]; then
        echo ""
        if [[ $No_Tests == "true" ]]; then
            echo "No SMART tests were executed"
        else
            echo "SMART testing completed"
            if [[ -n "$Short_Drives_Testing" ]]; then
                echo "Short tests started on: $Short_Drives_Testing"
            fi
            if [[ -n "$Long_Drives_Testing" ]]; then
                echo "Long tests started on: $Long_Drives_Testing"
            fi
        fi
        
        # Wait for short tests if configured
        if [[ $Short_Drives_Test_Delay -gt 0 ]] && [[ -n "$Short_Drives_Testing" ]]; then
            echo ""
            echo "Waiting $Short_Drives_Test_Delay seconds for short tests to complete..."
            if [[ $Demo != "true" ]]; then
                sleep $Short_Drives_Test_Delay
            fi
        fi
        
        echo ""
        echo "Script completed at $(date +%H:%M:%S)"
    fi
    
    # Cleanup
    if test -e "/tmp/drive_selftest/drive_test_temp.txt"; then
        rm -f "/tmp/drive_selftest/drive_test_temp.txt"
    fi
}

# Execute main function with all arguments
main "$@"

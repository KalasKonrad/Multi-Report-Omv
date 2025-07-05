# Multi-Report OMV Fork with Automated SMART Testing

## Overview

This enhanced OMV fork of Multi-Report provides comprehensive drive health monitoring and reporting for OpenMediaVault systems. The script combines detailed SMART analysis with **optional automated SMART testing** via the `drive_selftest_omv.sh` script, offering intelligent drive testing with load balancing - a powerful alternative to manually configuring individual drive tests in OMV's web interface.

## Installation

### Download from GitHub

```bash
# Clone the repository
git clone https://github.com/[your-username]/Multi-Report-OMV.git

# Navigate to the directory
cd Multi-Report-OMV

# Make scripts executable
chmod +x multi_report_omv.sh
chmod +x drive_selftest_omv.sh
chmod +x smr-check-omv.sh
```

### Basic Setup

1. **Copy the sample configuration**:
   ```bash
   cp multi_report_omv_config.txt.sample multi_report_omv_config.txt
   ```

2. **Edit configuration for your system**:
   ```bash
   sudo nano multi_report_omv_config.txt
   ```

3. **Test the installation**:
   ```bash
   sudo ./multi_report_omv.sh --help
   ```

### Prerequisites

- **OpenMediaVault** system (OMV 5.x or later recommended)
- **Root/sudo access** for SMART data collection
- **smartmontools** package (usually pre-installed on OMV)
- **Basic shell utilities** (lsblk, awk, sed - standard on Linux)

## Quick Start Overview

This enhanced OMV fork of Multi-Report provides comprehensive drive health monitoring and reporting for OpenMediaVault systems. The script combines detailed SMART analysis with **optional automated SMART testing** via the `drive_selftest_omv.sh` script, offering intelligent drive testing with load balancing - a powerful alternative to manually configuring individual drive tests in OMV's web interface.

## Core Features

### 📊 **Comprehensive SMART Analysis**
- **Multi-interface drive detection** - Automatic discovery of SATA, SAS, and NVMe drives
- **Detailed SMART attribute reporting** - Temperature, power-on hours, reallocated sectors, error counts
- **Drive health assessment** - Pass/fail status with detailed explanations for failures
- **OMV integration** - Extracts drive tags/comments from OpenMediaVault configuration
- **SMR detection** - Identifies Shingled Magnetic Recording drives and potential issues

### 📈 **Historical Data & Trending** 
- **CSV database** - Maintains comprehensive historical SMART data
- **Long-term trending** - Track drive health metrics over time
- **Configurable retention** - Automatic purging of old data based on age
- **Export capabilities** - Data suitable for spreadsheet analysis and graphing

### 📧 **Intelligent Email Notifications**
- **Configurable alerting levels** - Always, issues-only, or critical-only
- **Rich content** - Detailed drive status, test results, and health summaries  
- **HTML or plain text** - Flexible formatting options
- **Optional attachments** - Include log files and/or CSV data
- **Hostname integration** - Clear identification of reporting system

### 🔧 **System Integration**
- **OMV filesystem awareness** - Integrates with OpenMediaVault mount points and tags
- **Multiple filesystem support** - Works with ext4, btrfs, xfs, and other filesystems
- **Flexible scheduling** - Designed for cron-based automation
- **Safe operation** - Non-destructive analysis with comprehensive error handling

## What's New

### 🚀 Automated SMART Testing (`drive_selftest_omv.sh`)
- **Automatic drive discovery** - new drives are automatically included
- **Intelligent load balancing** - spreads tests across time to reduce system impact  
- **Smart scheduling** - configurable daily/weekly/monthly patterns
- **Drive cage awareness** - randomizes testing to avoid hitting drives in same enclosure
- **Zero configuration overlap** - prevents duplicate short/long tests on same drive same day

### 🎯 When to Use Automated Testing

**Use OMV Web Interface for:**
- Simple setups (< 10 drives)
- Basic monthly/weekly testing needs
- Standard home/small office use

**Use drive_selftest_omv.sh for:**
- Multiple drives (10+ drives) where individual scheduling is tedious
- Performance-critical systems requiring careful test timing
- Enterprise environments wanting load balancing
- Automatic handling of new drives
- Advanced scheduling patterns

## Quick Start

### Option 1: OMV Web Interface (Simple)
1. Go to **Storage > S.M.A.R.T.**
2. Configure tests for each drive individually
3. Set your desired schedule per drive

### Option 2: Automated Testing (Advanced)
1. **Configure**: Edit `multi_report_omv_config.txt`
   ```bash
   # Enable automated testing
   Short_Test_Mode=1                         # 1=spread, 2=all drives, 3=disabled
   Long_Test_Mode=1                          # 1=spread, 2=all drives, 3=disabled
   Short_Drives_to_Test_Per_Day=2            # How many drives per day
   Long_Drives_to_Test_Per_Day=1             # How many drives per day
   Short_Drives_Tested_Days_of_the_Week="1,2,3,4,5"  # Weekdays
   Long_Drives_Tested_Days_of_the_Week="6,7"          # Weekends
   ```

2. **Test Configuration**:
   ```bash
   sudo ./drive_selftest_omv.sh -config
   sudo ./drive_selftest_omv.sh -demo
   ```

3. **Schedule**: Add to cron
   ```bash
   sudo crontab -e
   # Add: 0 2 * * * /path/to/drive_selftest_omv.sh
   ```

4. **Integration**: Multi-Report will automatically call the testing script

## Basic Usage

### Manual Execution

Run Multi-Report manually to generate an immediate report:

```bash
# Standard report generation
sudo ./multi_report_omv.sh

# Test email configuration  
sudo ./multi_report_omv.sh --test-email

# Preview next scheduled SMART tests (doesn't run tests)
sudo ./multi_report_omv.sh --preview

# Help and version information
sudo ./multi_report_omv.sh --help
sudo ./multi_report_omv.sh --version
```

### Automated Scheduling

Set up automated reporting with cron:

```bash
# Edit root's crontab
sudo crontab -e

# Example: Daily report at 2:00 AM
0 2 * * * /path/to/multi_report_omv.sh

# Example: Weekly report on Sundays at 3:00 AM  
0 3 * * 0 /path/to/multi_report_omv.sh

# Example: Monthly report on the 1st at 4:00 AM
0 4 1 * * /path/to/multi_report_omv.sh
```

### Configuration Files

1. **Copy the sample configuration**:
   ```bash
   cp multi_report_omv_config.txt.sample multi_report_omv_config.txt
   ```

2. **Edit your configuration**:
   ```bash
   sudo nano multi_report_omv_config.txt
   ```

3. **Key settings to configure**:
   - Email settings (if using notifications)
   - SMART testing preferences (if using automated testing)
   - CSV data recording options
   - SMR detection settings

## Automated SMART Testing Configuration Examples

### Conservative (Default)
```bash
# Spreads short tests across weekdays (2 drives/day)
Short_Test_Mode=1
Short_Drives_to_Test_Per_Day=2
Short_Drives_Tested_Days_of_the_Week="1,2,3,4,5"

# Spreads long tests across weekends (1 drive/day) 
Long_Test_Mode=1
Long_Drives_to_Test_Per_Day=1
Long_Drives_Tested_Days_of_the_Week="6,7"
```

### Aggressive
```bash
# Daily short tests on all drives
Short_Test_Mode=2
Short_Drives_Tested_Days_of_the_Week="1,2,3,4,5,6,7"

# Weekly long tests on all drives (Sundays)
Long_Test_Mode=2  
Long_Drives_Tested_Days_of_the_Week="7"
```

### Disabled
```bash
# Use OMV web interface instead
Short_Test_Mode=3
Long_Test_Mode=3
```

## Features

### 🔧 Intelligent Scheduling
- **Spread Mode**: Distributes tests across time period
- **All Mode**: Tests all drives on specified days  
- **Disable Mode**: No automated testing
- **Load balancing**: Delays between drive tests
- **Conflict avoidance**: Short tests skip drives scheduled for long tests

### 📊 Integration
- **Multi-Report integration**: Called automatically during analysis
- **Shared configuration**: Uses same config file
- **Logging**: Integrated with Multi-Report logging
- **Email notifications**: Test results included in reports

### 🛡️ Safety Features
- **Root privilege checking**: Safe privilege escalation
- **Drive compatibility testing**: Multiple interface attempts
- **Error handling**: Graceful failure with reporting
- **Demo mode**: Test configuration without running tests

### 🚀 Advanced Features (v1.05)

The `drive_selftest_omv.sh` script is now based on the proven TrueNAS `drive_selftest.sh` v1.05, providing enterprise-grade capabilities:

#### **Enterprise Scheduling Intelligence**
- **Multiple test modes per type**: Spread, all-drives, or disabled for both short and long tests
- **Flexible time periods**: Weekly or monthly scheduling patterns
- **Day-of-week selection**: Precise control over when tests run (e.g., "1,2,3,4,5" for weekdays)
- **Load balancing delays**: Configurable delays between drive tests to prevent system overload
- **Drive ordering options**: Sort by drive ID or serial number for optimal cage distribution

#### **Advanced Drive Management** 
- **Automatic drive discovery**: Uses `lsblk` and `smartctl` for Linux/OMV compatibility
- **Drive exclusion**: Ignore specific drives by serial number
- **NVMe-only mode**: Option to test only NVMe drives
- **Interface fallback**: Multiple smartctl interface attempts for difficult drives
- **Drive type awareness**: Handles SATA, SAS, and NVMe drives appropriately

#### **System Integration**
- **Filesystem scrub awareness**: Detects ZFS scrubs and adjusts testing (for OMV ZFS users)
- **Scrub time thresholds**: Skip long tests if scrub has > X minutes remaining
- **Resilver detection**: Automatically defers testing during RAID rebuilds
- **Multiple SMART interfaces**: Attempts auto, sat, scsi, nvme connection types

#### **Professional Logging & Debugging**
- **Daily log rotation**: Creates `drive_test_XX.txt` files (01-31) with monthly rotation
- **Comprehensive timing**: Tracks test start/completion times with elapsed time calculation
- **Debug modes**: Multiple levels of debugging output for troubleshooting
- **Silent operation**: Minimal output mode for production cron jobs
- **Test progress tracking**: Monitors ongoing tests and provides status updates

#### **Operational Modes**
```bash
# Comprehensive help system
./drive_selftest_omv.sh -help

# Safe configuration testing
./drive_selftest_omv.sh -demo              # Simulate with fake drives

# Detailed troubleshooting
./drive_selftest_omv.sh -debug             # Enable debug output

# Production operation
./drive_selftest_omv.sh -silent            # Minimal output for cron

# Log management
./drive_selftest_omv.sh -clearlog          # Clear old log files
```

#### **Configuration Examples for Different Scenarios**

**Large Array (20+ drives)**:
```bash
# Spread short tests across work week (4 drives/day)
Short_Test_Mode=1
Short_Drives_to_Test_Per_Day=4
Short_Drives_Test_Period="Week"
Short_Drives_Tested_Days_of_the_Week="1,2,3,4,5"

# Spread long tests across entire year (1 drive every few days)  
Long_Test_Mode=1
Long_Drives_to_Test_Per_Day=1
Long_Drives_Test_Period="Annual"
Long_Drives_Tested_Days_of_the_Week="6,7"
```

**Performance-Critical System**:
```bash
# Minimal short testing (weekends only)
Short_Test_Mode=1
Short_Drives_to_Test_Per_Day=2
Short_Drives_Tested_Days_of_the_Week="6,7"

# Long tests spread across 6 months, weekends only
Long_Test_Mode=1
Long_Drives_to_Test_Per_Day=1
Long_Drives_Test_Period="Biannual"
Long_Drives_Tested_Days_of_the_Week="7"
```

**High-Availability System**:
```bash
# Conservative short testing
Short_Test_Mode=1
Short_Drives_to_Test_Per_Day=1
Short_Time_Delay_Between_Drives=300        # 5-minute delays

# Long tests only once per year during maintenance windows
Long_Test_Mode=1
Long_Drives_Test_Period="Annual"
Long_Drives_Tested_Days_of_the_Week="7"    # Sundays only
```

#### **Flexible Test Period Options**

The script now supports extended test periods to reduce the frequency of intensive long tests:

- **Week** (7 days) - Good for small arrays with frequent testing needs
- **Month** (28 days) - Traditional monthly testing cycle
- **Quarter** (90 days) - **Recommended for most users** - balances thoroughness with system impact
- **Biannual** (180 days) - Good for large arrays or performance-critical systems
- **Annual** (365 days) - Enterprise-grade for massive arrays (100+ drives)

**Frequency Comparison**:
- Monthly: Each drive tested ~12 times per year
- Quarterly: Each drive tested ~4 times per year (**recommended**)
- Biannual: Each drive tested ~2 times per year
- Annual: Each drive tested ~1 time per year

This enterprise-grade testing system scales from small home servers to large storage arrays while maintaining intelligent load balancing and comprehensive monitoring integration.

## Commands

```bash
# Configuration and testing
./drive_selftest_omv.sh -config          # Show current config
./drive_selftest_omv.sh -drives          # List discovered drives  
./drive_selftest_omv.sh -demo            # Show what would run
./drive_selftest_omv.sh -debug           # Enable debug output

# Manual execution
./drive_selftest_omv.sh -short           # Run short tests only
./drive_selftest_omv.sh -long            # Run long tests only
./drive_selftest_omv.sh                  # Run scheduled tests

# Multi-Report integration
./multi_report_omv.sh                    # Includes automated testing
./multi_report_omv.sh --test-email       # Test email notifications
```

## File Structure

```
Multi-Report-Omv/
├── multi_report_omv.sh                      # Main analysis script
├── multi_report_omv_config.txt.sample       # Sample configuration file
├── drive_selftest_omv.sh                    # Automated testing script
├── smr-check-omv.sh                         # SMR detection script
└── README.md                                # This documentation
```

## Benefits Over Manual Scheduling

| Feature | OMV Web Interface | drive_selftest_omv.sh |
|---------|-------------------|----------------------|
| **Setup Time** | High (per drive) | Low (bulk config) |
| **New Drive Handling** | Manual addition | Automatic discovery |
| **Load Balancing** | Manual calculation | Intelligent spreading |
| **Drive Cage Awareness** | None | Serial-based randomization |
| **Conflict Prevention** | Manual coordination | Automatic deduplication |
| **Scheduling Flexibility** | Limited patterns | Complex weekly/monthly patterns |
| **Scrub Integration** | None | ZFS scrub awareness |
| **Debug Capabilities** | None | Comprehensive debug modes |
| **Logging** | Basic | Daily rotation with timing |
| **Drive Filtering** | Manual | Serial number exclusion |
| **Interface Handling** | Basic | Multiple fallback attempts |
| **Enterprise Features** | Limited | Full enterprise capabilities |
| **Maintenance** | High | Low |

## Troubleshooting

### Permission Issues
```bash
# Make script executable
sudo chmod +x drive_selftest_omv.sh

# Check root access
sudo ./drive_selftest_omv.sh -debug
```

### No Drives Found
```bash
# Check drive discovery
sudo ./drive_selftest_omv.sh -drives

# Manual drive check
sudo smartctl --scan
lsblk -d
```

### Configuration Issues
```bash
# Verify config loading
sudo ./drive_selftest_omv.sh -config

# Test demo mode
sudo ./drive_selftest_omv.sh -demo
```

## Email Notifications

Multi-Report OMV includes comprehensive email notification capabilities to keep you informed of drive health status and test results.

### Email Configuration

Configure email notifications in `multi_report_omv_config.txt`:

```bash
# Email Configuration
Email_Enable=true                                 # Enable/disable email notifications
Email_To="admin@example.com"                     # Recipient email address
Email_From="multireport@yourdomain.com"          # Sender email address
Email_Subject_Prefix="[Multi-Report]"            # Subject line prefix
Email_Include_Hostname=true                      # Include hostname in subject
Email_Use_HTML=false                             # Use HTML formatting (false=plain text)
Email_Attach_Logs=false                          # Attach log files to email
Email_Attach_CSV=false                           # Attach CSV data file to email
Email_Level="issues"                             # When to send: "always", "issues", "critical"
```

### Email Levels

- **`always`**: Send email after every report run
- **`issues`** (default): Send email when warnings or critical issues are detected
- **`critical`**: Send email only for critical drive failures or errors

### Test Email Configuration

Verify your email setup:

```bash
sudo ./multi_report_omv.sh --test-email
```

This will send a test email using your current configuration and verify that the email system is working properly.

### Email Content

Emails include:
- **Summary**: Overall system health status
- **Drive Details**: Individual drive SMART status and key metrics
- **Test Results**: Results from automated SMART testing (if enabled)
- **Warnings/Errors**: Any detected issues requiring attention
- **Optional Attachments**: Log files and/or CSV data (if configured)

## CSV Data Recording & Analysis

Multi-Report OMV can maintain a comprehensive CSV database of SMART data over time, providing historical trending and analysis capabilities.

### CSV Configuration

```bash
# CSV/Statistical Data Recording
SDF_DataRecordEnable=true                        # Enable CSV data recording
Statistical_Data_File="$SCRIPT_DIR/statisticalsmartdata_omv.csv"  # CSV file location
SDF_DataPurgeDays=730                           # Purge CSV data older than X days (0=never)
CSV_File_Owner="root"                           # CSV file owner
CSV_File_Group="root"                           # CSV file group  
CSV_File_Permissions="644"                      # CSV file permissions
```

### CSV Data Fields

The CSV file captures comprehensive SMART metrics for each drive:

| Field | Description |
|-------|-------------|
| **Date/Time** | Timestamp of data collection |
| **Device ID** | Drive device identifier (/dev/sdX) |
| **Mountpoint** | Where the drive is mounted |
| **Filesystem Name** | Logical filesystem name |
| **Filesystem Type** | Type (ext4, btrfs, xfs, etc.) |
| **OMV Tag** | OpenMediaVault tag/comment |
| **Drive Type** | SATA, SAS, NVMe identification |
| **Serial Number** | Drive serial number |
| **SMART Status** | Overall SMART health (PASSED/FAILED) |
| **Temperature** | Current drive temperature |
| **Power On Hours** | Total hours drive has been powered on |
| **Wear Level** | SSD wear leveling (if available) |
| **Start Stop Count** | Number of drive start/stop cycles |
| **Load Cycle** | Number of load/unload cycles |
| **Spin Retry** | Spin retry count |
| **Reallocated Sectors** | Number of reallocated sectors |
| **Reallocated Events** | Number of reallocation events |
| **Pending Sectors** | Sectors pending reallocation |
| **Offline Uncorrectable** | Offline uncorrectable sectors |
| **UDMA CRC Errors** | Interface CRC error count |
| **Seek Error Rate** | Raw seek error rate |
| **Multi Zone Errors** | Multi-zone error rate |
| **Read Error Rate** | Raw read error rate |
| **SMR Status** | Shingled Magnetic Recording detection |
| **Total MB Written** | Lifetime data written (SSD) |
| **Total MB Read** | Lifetime data read (SSD) |

### Using CSV Data

The CSV file can be:
- **Imported into spreadsheet applications** for analysis and graphing
- **Processed with data analysis tools** (Python pandas, R, etc.)
- **Monitored for trends** in drive health metrics
- **Used for predictive failure analysis** 
- **Attached to email reports** for historical context

### CSV Data Management

- **Automatic purging**: Old records are automatically removed based on `SDF_DataPurgeDays`
- **Header preservation**: CSV headers are maintained during purging operations
- **File permissions**: Configurable ownership and permissions for security
- **Backup integration**: CSV file can be included in backup routines

This automated testing system provides enterprise-grade drive health management while maintaining the simplicity and analysis power of Multi-Report.

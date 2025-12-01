# Multi-Report-OMV v2.0

**Modern SMART monitoring and reporting system for OpenMediaVault**

Version 2.0 is a complete rewrite with a modular plugin architecture, improved privilege management, and enhanced maintainability.

## Features

- 🔐 **Sudo Management** - Single password prompt with background keepalive
- 📊 **SMART Monitoring** - Comprehensive drive health tracking
- 📧 **Email Notifications** - HTML and text report delivery
- 📈 **Statistical Recording** - Historical data tracking in CSV format
- 🔄 **Drive Self-Testing** - Automated short/long test scheduling
- 🎯 **Plugin Architecture** - Modular and extensible design
- 📝 **Structured Logging** - Color-coded console output and file logging
- ⚙️ **Configuration Management** - Centralized settings with validation

## Quick Start

```bash
# Show version
./bin/multi-report-omv --version

# Check system status (will prompt for sudo password once)
./bin/multi-report-omv status

# Show configuration
./bin/multi-report-omv config show

# Get help
./bin/multi-report-omv --help
```

## Installation

Multi-Report-OMV v2.0 supports local installation (no root required):

```bash
cd ~/docker/system/scripts/multi-report-omv/version2
./bin/multi-report-omv status
```

## Requirements

- OpenMediaVault 7.x (tested on 7.7.18)
- Bash 4.0+
- `smartmontools` package (smartctl)
- `sudo` configured for user (or run as root)
- Standard GNU utilities (awk, sed, grep, etc.)

## Configuration

Configuration files are stored in `config/`:

- `defaults.conf` - Default settings (auto-generated)
- `multi-report-omv.conf` - User overrides (create to customize)

Key settings:

```bash
# Sudo behavior
REQUIRE_ROOT=false      # Set true to require direct root execution
DISABLE_SUDO=false      # Set true to disable sudo elevation

# Email notifications
EMAIL_ENABLED=false     # Enable email reports
EMAIL_TO=""            # Recipient address
EMAIL_FROM="..."       # Sender address

# SMART monitoring
SMART_ENABLED=true     # Enable SMART monitoring
TEMP_WARN_HDD=45       # Warning temperature for HDDs
TEMP_CRIT_HDD=50       # Critical temperature for HDDs

# Drive self-tests
SELFTEST_ENABLED=true          # Enable automated testing
SELFTEST_SHORT_PERIOD=Week     # Short test frequency
SELFTEST_LONG_PERIOD=Quarter   # Long test frequency
```

## Architecture

```
version2/
├── bin/
│   └── multi-report-omv      # Main executable
├── core/
│   ├── logger.sh             # Logging system
│   ├── utils.sh              # Utility functions
│   └── config.sh             # Configuration management
├── plugins/
│   ├── drive-selftest/       # Drive testing plugin
│   ├── smart-monitor/        # SMART monitoring plugin
│   └── email-notify/         # Email notification plugin
├── config/
│   └── multi-report-omv.conf # User configuration
├── logs/
│   └── multi-report-omv.log  # Application log
└── docs/
    ├── DEVELOPMENT-PROGRESS.md  # Complete progress tracking and session notes
    └── SUDO-MANAGEMENT.md       # Technical reference for sudo system
```

## Usage

### System Status

Check OMV version and detect SMART-capable drives:

```bash
./bin/multi-report-omv status
```

### Configuration Management

```bash
# Show current configuration
./bin/multi-report-omv config show

# Edit configuration file
nano config/multi-report-omv.conf
```

### Running Tests

```bash
# Run drive self-tests (upcoming)
./bin/multi-report-omv test

# Run SMART analysis (upcoming)
./bin/multi-report-omv smart

# Generate report (upcoming)
./bin/multi-report-omv report
```

## Sudo Management

Multi-Report-OMV v2.0 uses a sophisticated sudo privilege management system:

- **Single password prompt** at startup
- **Background keepalive** refreshes sudo every 60 seconds
- **Automatic cleanup** on script exit
- **Configurable behavior** (require root, disable sudo, etc.)

See `docs/SUDO-MANAGEMENT.md` for detailed documentation.

## Development Status

**Current Version:** 2.0.0-dev  
**Branch:** v2.0-dev

### Completed ✅
- Core architecture and modules (100%)
- Sudo privilege management system (100%)
- Logging and configuration systems (100%)
- Configuration backup/restore (100%)
- Configuration migration system (100%)
- Notification framework (pluggable delivery) (100%)
- Plugin system with discovery and execution (95%)
- Drive detection (8 drives tested) (100%)
- Statistical data collection plugin (100%)
- Selftest rotation plugin (100%)
- SMR detection plugin (100%)
- Report generation plugin (100%)
- OMV 7 integration (100%)

### In Progress 🔄
- Real-world testing and validation (60%)
- Sleeping drive behavior verification (ongoing)
- Email notification testing (pending)
- Report system end-to-end testing (pending)

### Planned ⏳
- Long-term stability testing
- Cron job integration
- User documentation and guides
- Migration tools from v1.x

See `docs/DEVELOPMENT-PROGRESS.md` for complete development progress, session notes, and detailed status tracking.

## Differences from v1.x

| Feature | v1.x | v2.0 |
|---------|------|------|
| Architecture | Monolithic | Modular plugins |
| Privilege Model | Root only | Sudo with keepalive |
| Configuration | Inline variables | Structured config file |
| Logging | Basic echo | Structured with levels |
| Extensibility | None | Plugin-based |
| Code Organization | Single file | Separated modules |
| Error Handling | Ad-hoc | Centralized validation |
| Documentation | Minimal | Comprehensive |

## Contributing

This is a personal project for OpenMediaVault systems. Development tracking and progress documentation are available in the `docs/` directory.

## License

Personal project - see main repository for license information.

## Support

For issues or questions:
- Check `docs/` directory for detailed documentation
- Review the development progress in `docs/DEVELOPMENT-PROGRESS.md`
- Examine log files in `logs/multi-report-omv.log`

## Acknowledgments

- Architecture inspired by [SnapRAID Manager](https://github.com/Accusedbold/SnapRAID-Manager)
- Designed for OpenMediaVault 7.x systems
- Uses `smartmontools` for SMART data access

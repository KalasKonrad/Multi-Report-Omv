# Multi-Report-OMV v2.0 - New Structure

Following the proven architecture from SnapRAID Manager v2.0

## Directory Layout

```
version2/
├── bin/                          # Executable scripts
│   └── multi-report-omv         # Main entry point
│
├── core/                         # Core system modules
│   ├── logger.sh                # Logging system
│   ├── config.sh                # Configuration management
│   ├── config-backup.sh         # Configuration backup/restore
│   ├── config-migration.sh      # Configuration version migration
│   ├── plugin.sh                # Plugin discovery and execution
│   └── utils.sh                 # Shared utilities (includes SMART, CSV, email functions)
│
├── plugins/                      # Modular components
│   ├── report/                  # Report generation plugin
│   │   ├── manifest.json
│   │   └── report.sh
│   ├── selftest/                # Drive self-test scheduling plugin
│   │   ├── manifest.json
│   │   └── selftest.sh
│   ├── smr_check/               # SMR/CMR detection plugin
│   │   ├── manifest.json
│   │   └── smr_check.sh
│   └── statistical_data/        # SMART data collection and analysis plugin
│       ├── manifest.json
│       └── statistical_data.sh
│
├── config/                       # Configuration files
│   ├── multi-report-omv.conf    # Main configuration
│   └── defaults.conf            # Default values
│
├── logs/                         # Log files (timestamped)
│
├── data/                         # Runtime data
├── tmp/                          # Temporary working directory
│
├── tools/                        # Development and maintenance tools
│
├── docs/                         # Documentation
├── tmp/                          # Temporary working directory
│
├── docs/                         # Documentation
│   ├── README.md
│   ├── CONFIGURATION.md
│   ├── TROUBLESHOOTING.md
│   └── MIGRATION.md             # v1 to v2 migration guide
│
├── VERSION                       # Single source of truth for version
├── CHANGELOG.md
└── Function-Manifest.md          # All functions documented

```

## Design Principles

### 1. Modularity
- Separate concerns into individual library files
- Each module has a single responsibility
- Easy to test individual components

### 2. Configuration
- Single configuration file (not embedded in scripts)
- Clear separation of user settings vs code
- Validation on startup

### 3. Logging
- Consistent logging throughout all components
- Log levels: DEBUG, INFO, WARNING, ERROR
- Both file and syslog output

### 4. Error Handling
- Explicit error codes
- Graceful degradation
- Clear error messages with actionable advice

### 5. Testability
- Functions designed to be testable
- Mock data for testing
- No hard-coded paths (use config)

## Key Changes from v1.x

### Script Organization
- **Old**: Monolithic scripts with embedded functions
- **New**: Modular library system with clear interfaces
- **Note**: SMART, CSV, and email functions consolidated in `utils.sh` for simplicity

### Configuration
- **Old**: Variables at top of script files
- **New**: Separate config file with validation
- **Implemented**: `config.sh` handles both defaults and user config with CONFIG array
- **Backup/Restore**: `config-backup.sh` provides automatic backup/restore functionality  
- **Migration**: `config-migration.sh` handles version upgrades and variable renames

### Logging
- **Old**: Echo to stdout/stderr
- **New**: Proper logging framework with levels (DEBUG, INFO, WARNING, ERROR)
- **Implemented**: Full logging system with file output, log rotation, and exported log level to plugins

### Plugin System
- **New in v2.0**: Dynamic plugin discovery and execution via `plugin.sh`
- **Implemented**: Plugins can be called individually or via `auto` command
- **Note**: Plugins do NOT source core modules - they inherit from main script

### Data Storage
- **Old**: Files in script directory
- **New**: Organized data directory structure
- **Implemented**: Each plugin has its own data subdirectory under `version2/data/`

### Error Handling
- **Old**: Continue on errors
- **New**: Explicit error handling with recovery

## Implementation Plan

### Phase 1: Core Infrastructure
1. Create common.sh with logging and config loading
2. Create config file structure
3. Test configuration loading and logging

### Phase 2: SMART Functions
1. Extract SMART data collection to smart.sh
2. Extract drive detection to drive-detection.sh
3. Test SMART data functions

### Phase 3: Scheduling Logic
1. Rewrite drive test scheduling in scheduling.sh
2. Implement proper rotation algorithm
3. Test with various drive counts and configurations

### Phase 4: Main Scripts
1. Create new multi-report-omv main script
2. Create new drive-selftest script
3. Integrate all library modules

### Phase 5: Email and Reporting
1. Extract email functions to email.sh
2. Create email templates
3. Implement HTML formatting improvements

### Phase 6: Polish
1. Error handling and validation
2. Documentation
3. Testing on live system
4. Migration guide from v1.x

## Backward Compatibility

### Config Migration
- Provide tool to migrate v1.x config to v2.0 format
- Support reading old config files (with deprecation warnings)

### Data Migration
- Keep CSV format compatible
- Preserve historical data

### Script Names
- Maintain old script names as symlinks/wrappers
- Allow gradual transition

## File Naming Conventions

- Scripts: lowercase with hyphens (multi-report-omv)
- Libraries: lowercase with .sh extension (common.sh)
- Config: lowercase with .conf extension
- Documentation: UPPERCASE.md for main docs

## Next Steps

1. Review this structure with user
2. Create common.sh with basic logging
3. Create config file structure
4. Start migrating functionality module by module

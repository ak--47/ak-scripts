# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a collection of bash scripts for working with cloud storage (primarily Google Cloud Storage and AWS S3). The scripts provide utilities for counting lines, searching text, copying data, and listing bucket contents with parallel processing capabilities.

## Scripts Architecture

### Core Functionality
- **Line Counting**: Scripts that count lines in cloud storage files with concurrent processing
- **Text Search**: Tools for finding exact string matches across cloud storage files
- **Data Transfer**: Utilities for copying/mirroring between cloud storage locations
- **File Listing**: Human-readable tree views of bucket/folder structures

### Script Loading System
The repository uses `autoload.zsh` to automatically load all `.sh` files as functions in zsh:
- Auto-discovers and loads all scripts from `~/scripts/`
- Creates aliases for easy command-line access
- Provides `list_scripts` and `reload_scripts` helper functions
- Add `source ~/scripts/autoload.zsh` to `~/.zshrc` for automatic loading

## Available Scripts

### count_lines_simple.sh
Simplified line counter for macOS with no file locking (optimized for performance).
```bash
count_lines_simple "gs://bucket/path/*.tsv.gz" 8
```

### count_lines.sh
Full-featured line counter with support for GCS, S3, and Azure blob storage.
```bash
count_lines "gs://bucket/path/*.txt" 8
count_lines "s3://bucket/path/*.csv" 12
```

### find_string.sh
Simple string finder that stops at first match.
```bash
find_string "gs://bucket/path/*.txt" "search_text" 8
```

### find_matching_string.sh
Advanced string search with progress tracking and batch processing.
```bash
find_matching_string "gs://bucket/path/*.json" "needle_text" 8
```

### copy_bucket.sh
Copy or mirror objects between cloud storage locations.
```bash
# Copy files
copy_bucket 'gs://src/*.json' gs://dest/

# Mirror with sync and delete
copy_bucket --mirror gs://src-bucket gs://dest-bucket
copy_bucket --mirror --dry-run gs://src gs://dest
```

### list_bucket_folders.sh
Display human-readable tree of folders in GCS buckets.
```bash
list_bucket_folders gs://bucket/prefix/
list_bucket_folders gs://bucket/ --skip-dates
```

## Common Usage Patterns

### Prerequisites
- Google Cloud: `gsutil` must be installed and configured
- AWS: `aws` CLI must be installed and configured
- All scripts support concurrent processing with configurable parallelism

### Error Handling
Scripts include comprehensive error handling for:
- Missing cloud CLI tools
- Invalid file paths
- Permission issues
- Network timeouts

### Performance Optimization
- Scripts use parallel processing via `xargs -P` with configurable concurrency (default: 8)
- Temporary files are automatically cleaned up
- Progress indicators for long-running operations
- File locking mechanisms prevent race conditions

## Development Notes

### Script Structure
All scripts follow a consistent pattern:
1. Function definition with parameter validation
2. Cloud storage type detection (GCS/S3/Azure)
3. Tool availability checks
4. Parallel processing implementation
5. Results aggregation and cleanup
6. Export function and direct execution support

### Testing Scripts
Test individual scripts by running them directly:
```bash
./count_lines_simple.sh "gs://test-bucket/*.txt" 8
```

### Adding New Scripts
1. Create new `.sh` file in the scripts directory
2. Follow the existing naming and structure patterns
3. Include usage documentation in script header
4. Export main function for autoloader compatibility
5. Run `reload_scripts` to make available in current shell
# ak-scripts

A collection of bash scripts for cloud storage operations with concurrent processing capabilities.

## Quick Setup

### For Zsh (default on macOS)

Add these lines to your `~/.zshrc`:

```bash
export SCRIPTS_DIR="$HOME/ak-scripts"  # Optional: customize location (defaults to ~/scripts)
source ~/ak-scripts/autoload.zsh
```

Then reload: `source ~/.zshrc`

### For Bash (Linux/other terminals)

Add these lines to your `~/.bashrc`:

```bash
export SCRIPTS_DIR="$HOME/ak-scripts"  # Optional: customize location (defaults to ~/scripts)
source ~/ak-scripts/autoload.bash
```

Then reload: `source ~/.bashrc`

**Note:** If your scripts are in `~/scripts`, you don't need to set `SCRIPTS_DIR`.

## Available Commands

Once loaded, you can run any script by name:

- `count_lines_simple` - Fast line counter for GCS files
- `count_lines` - Multi-cloud line counter (GCS/S3/Azure)
- `find_string` - Find first string match in cloud files
- `find_matching_string` - Advanced string search with progress
- `copy_bucket` - Copy/mirror between cloud storage
- `list_bucket_folders` - Tree view of GCS bucket folders
- `list_scripts` - Show all available scripts
- `reload_scripts` - Refresh script functions

## Examples

```bash
# Count lines in compressed files
count_lines_simple "gs://bucket/data/*.tsv.gz" 20

# Search for text across files
find_string "gs://bucket/logs/*.json" "error_message" 10

# Copy data between buckets
copy_bucket "gs://source/*.csv" gs://destination/

# Mirror buckets (with delete)
copy_bucket --mirror gs://source-bucket gs://dest-bucket
```

## Requirements

- **Google Cloud**: `gsutil` CLI tool
- **AWS**: `aws` CLI tool
- **macOS/Linux**: bash, xargs with -P support

All scripts include usage help - run any command without arguments to see options.
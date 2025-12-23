# Configurable Media Data Path

This project supports configurable media data paths to allow testing with different datasets without copying files.

## Configuration

Set the `MEDIA_DATA_PATH` environment variable in your `.env.local` file:

```bash
# Option 1: Relative path (relative to project root)
MEDIA_DATA_PATH="test-data"

# Option 2: Absolute path
MEDIA_DATA_PATH="/Volumes/BeeDrive/Libation"

# Option 3: Custom directory
MEDIA_DATA_PATH="/path/to/my/audiobooks"
```

## Usage

### For Development Testing

```bash
# Use small test dataset (default)
MEDIA_DATA_PATH="test-data"

# Run import
npm run import
```

### For Large Dataset Testing

```bash
# Point to your full Libation library
MEDIA_DATA_PATH="/Volumes/BeeDrive/Libation"

# Run import
npm run import
```

### For Production

```bash
# Use production data location
MEDIA_DATA_PATH="/mnt/audiobooks"
```

## How It Works

1. **Import Script** (`npm run import`)
   - Reads from `LIBATION_PATH` (if set) or `MEDIA_DATA_PATH`
   - Falls back to `test-data` if neither is set
   - Stores relative paths in database

2. **Image API** (`/api/images/[...path]`)
   - Serves files from `MEDIA_DATA_PATH` directory
   - Validates paths for security (prevents directory traversal)

3. **Media Utilities** (`lib/media.ts`)
   - `getMediaPath()` - Get configured media path
   - `getAbsoluteMediaPath()` - Get absolute path
   - `validateMediaPath()` - Security validation

## Environment Variables

| Variable          | Purpose                                       | Default     |
| ----------------- | --------------------------------------------- | ----------- |
| `MEDIA_DATA_PATH` | Where media files are stored                  | `test-data` |
| `LIBATION_PATH`   | Source for import (overrides MEDIA_DATA_PATH) | -           |

## Security

- Path validation prevents directory traversal attacks
- Only files within the configured media directory can be accessed
- Absolute paths are resolved and checked before serving files

## Example Workflow

```bash
# 1. Set up with small dataset for quick development
echo 'MEDIA_DATA_PATH="test-data"' >> .env.local
npm run import
npm run dev

# 2. Test with larger dataset without copying
echo 'MEDIA_DATA_PATH="/Volumes/ExternalDrive/Audiobooks"' >> .env.local
npm run import  # Re-imports from new location
npm run dev     # Images now served from new location

# 3. Back to small dataset
echo 'MEDIA_DATA_PATH="test-data"' >> .env.local
npm run import
```

## Notes

- Database stores relative paths, so you can switch between datasets
- Re-import required when changing `MEDIA_DATA_PATH`
- For import, `LIBATION_PATH` takes precedence over `MEDIA_DATA_PATH`
- Both absolute and relative paths are supported

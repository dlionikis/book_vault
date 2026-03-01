# Audible Download Automation Plan

> **Created**: March 1, 2026
> **Status**: Planned
> **Priority**: Medium
> **Dependencies**: Python 3.10+, `audible-cli`, `ffmpeg`, AWS CLI

---

## Overview

Replace the manual Libation GUI workflow with a Python script that:

1. Authenticates with your Audible account
2. Downloads a specific audiobook (or new purchases since last run)
3. Extracts metadata and generates Libation-compatible `.metadata.json`
4. Saves files locally in the same folder structure Libation uses
5. Uploads to S3 (`book-vault-media`)
6. Optionally triggers the existing `import-libation.ts` to register in the database

### Current Workflow (Manual)

```
Open Libation GUI → Scan library → Select book → Download →
Wait for DRM removal → Files appear in Libation folder →
Manually run: aws s3 sync ... → Manually run: npm run import
```

### Target Workflow (Automated)

```
python scripts/audible-download.py --asin B0XXXXXXXX
  → Downloads audio + cover + chapters
  → Generates .metadata.json (Libation-compatible)
  → Saves to local folder
  → Uploads to S3
  → Runs database import
  → Done. Ready to play in Book Vault.
```

Or for batch:

```
python scripts/audible-download.py --new
  → Finds all books purchased since last run
  → Downloads and processes each one
```

---

## Architecture

### Tool Stack

| Tool                           | Purpose                                                    |
| ------------------------------ | ---------------------------------------------------------- |
| `audible` (Python library)     | Authenticate, fetch metadata via Audible API               |
| `audible-cli`                  | Download AAXC files, DRM removal, cover + chapter download |
| `ffmpeg`                       | Audio conversion (AAXC → M4B), chapter extraction          |
| `boto3`                        | Upload to S3                                               |
| Script (`audible-download.py`) | Orchestration, metadata transformation, folder management  |

### Data Flow

```
Audible API
  │
  ├── GET /1.0/library?response_groups=contributors,product_attrs,
  │     product_desc,series,category_ladders,rating,reviews
  │   → Full metadata (authors, narrators, series, categories, etc.)
  │
  ├── audible download -a ASIN --aaxc --cover --cover-size 1215 --chapter
  │   → Audio file (.aaxc → .m4b via ffmpeg)
  │   → Cover image (.jpg, 1215px)
  │   → Chapter metadata (.json)
  │
  └── Transform metadata → Libation .metadata.json format
      │
      ├── Save to local folder: {output_dir}/{Title} [{ASIN}]/
      │   ├── {Title} [{ASIN}].m4b
      │   ├── {Title} [{ASIN}].jpg
      │   └── {Title} [{ASIN}].metadata.json
      │
      ├── Upload folder to S3: s3://book-vault-media/{Title} [{ASIN}]/
      │
      └── Run: npm run import (registers in Book Vault database)
```

---

## Metadata Mapping

The critical piece: mapping Audible API response fields to the `LibationMetadata` interface your `import-libation.ts` expects.

### Audible API → LibationMetadata

```python
# Audible API response (from /1.0/library with full response_groups)
audible_item = {
    "asin": "B0XXXXXXXX",
    "title": "A Darker Shade of Magic",
    "authors": [
        {"asin": "B00IJ0ETGY", "name": "V. E. Schwab"}
    ],
    "narrators": [
        {"name": "Steven Crossley"}
    ],
    "series": [
        {"asin": "B00TOCRRDC", "title": "Shades of Magic", "sequence": "1"}
    ],
    "publisher_summary": "<p>Kell is one of the last...</p>",
    "runtime_length_min": 563,
    "release_date": "2015-02-24",
    "publisher_name": "Tantor Audio",
    "product_images": {
        "1215": "https://m.media-amazon.com/images/I/..."
    },
    "category_ladders": [
        {
            "root": "Genres",
            "ladder": [
                {"id": "18574426011", "name": "Science Fiction & Fantasy"},
                {"id": "18574434011", "name": "Fantasy"}
            ]
        }
    ],
    "rating": {
        "overall_distribution": {...},
        "num_reviews": 342
    },
    "customer_reviews": [...]
}

# Transformed to LibationMetadata format
libation_metadata = {
    "asin": "B0XXXXXXXX",
    "title": "A Darker Shade of Magic",
    "authors": [
        {"name": "V. E. Schwab", "asin": "B00IJ0ETGY"}
    ],
    "narrators": [
        {"name": "Steven Crossley"}
    ],
    "series": [
        {"title": "Shades of Magic", "sequence": "1", "asin": "B00TOCRRDC"}
    ],
    "publisher_summary": "Kell is one of the last...",  # HTML stripped
    "category_ladders": [
        {
            "root": "Genres",
            "ladder": [
                {"id": "18574426011", "name": "Science Fiction & Fantasy"},
                {"id": "18574434011", "name": "Fantasy"}
            ]
        }
    ],
    "runtime_length_min": 563,
    "release_date": "2015-02-24",
    "publisher": "Tantor Audio",
    # Additional fields your import script stores in the metadata JSON blob
    "rating": {...},
    "customer_reviews": [...]
}
```

The mapping is nearly 1:1 because Libation pulls from the same Audible API. The only differences are minor field name changes (`publisher_name` → `publisher`) and HTML-to-text conversion for `publisher_summary`.

---

## Implementation

### Phase 1: Setup & Authentication

**Time estimate**: 1 hour

#### Install dependencies

```bash
# Install audible-cli
pip install audible-cli

# Or with uv (recommended)
uv tool install audible-cli

# Verify
audible --version
```

#### One-time authentication

```bash
# Interactive setup — creates config + auth file in ~/.audible/
audible quickstart

# Prompts for:
# - Audible email
# - Country code (us)
# - Password (opens browser for OAuth)
# - Optional: encrypt auth file with password
```

This creates `~/.audible/config.toml` and `~/.audible/auth.json`. The auth file contains your Audible session token and can be reused indefinitely (auto-refreshes).

#### Verify it works

```bash
# List your library
audible library list

# Export full library metadata as JSON
audible library export --output /tmp/library.json --format json
```

---

### Phase 2: Python Script

**Time estimate**: 4-6 hours

```python
#!/usr/bin/env python3
"""
audible-download.py — Download audiobooks from Audible, transform metadata
to Libation format, save locally, and upload to S3.

Usage:
    python scripts/audible-download.py --asin B0XXXXXXXX
    python scripts/audible-download.py --asin B0XXXXXXXX --skip-s3
    python scripts/audible-download.py --new
    python scripts/audible-download.py --list
"""

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime
from html import unescape
from pathlib import Path

import audible
import boto3

# Configuration
DEFAULT_OUTPUT_DIR = os.environ.get(
    "AUDIBLE_OUTPUT_DIR",
    os.path.expanduser("~/Audiobooks")
)
S3_BUCKET = os.environ.get("AWS_S3_BUCKET", "book-vault-media")
AWS_PROFILE = os.environ.get("AWS_PROFILE", "book_vault")
AUDIBLE_AUTH_FILE = os.path.expanduser("~/.audible/auth.json")
LAST_RUN_FILE = os.path.expanduser("~/.audible/last_download_run.txt")

# Audible API response groups needed for full metadata
RESPONSE_GROUPS = ",".join([
    "contributors",
    "product_attrs",
    "product_desc",
    "product_extended_attrs",
    "series",
    "category_ladders",
    "rating",
    "reviews",
    "media",
    "relationships",
])


def get_audible_client():
    """Create authenticated Audible API client."""
    auth = audible.Authenticator.from_file(AUDIBLE_AUTH_FILE)
    return audible.Client(auth=auth)


def strip_html(html_text):
    """Strip HTML tags and decode entities."""
    if not html_text:
        return None
    clean = re.sub(r'<[^>]+>', '', html_text)
    return unescape(clean).strip()


def sanitize_filename(name):
    """Remove characters that are invalid in filenames."""
    # Remove or replace invalid characters
    sanitized = re.sub(r'[<>:"/\\|?*]', '', name)
    # Collapse multiple spaces
    sanitized = re.sub(r'\s+', ' ', sanitized).strip()
    # Truncate to reasonable length
    return sanitized[:200]


def fetch_book_metadata(client, asin):
    """Fetch full metadata for a single book from the Audible API."""
    print(f"  Fetching metadata for {asin}...")

    # Get from library endpoint (includes purchase-specific data)
    try:
        library = client.get(
            "1.0/library",
            response_groups=RESPONSE_GROUPS,
            num_results=1000,
        )

        # Find the specific book
        for item in library.get("items", []):
            if item.get("asin") == asin:
                return item
    except Exception as e:
        print(f"  Warning: Library lookup failed: {e}")

    # Fallback: try catalog endpoint
    try:
        product = client.get(
            f"1.0/catalog/products/{asin}",
            response_groups=RESPONSE_GROUPS,
            image_sizes="1215,500",
        )
        return product.get("product", product)
    except Exception as e:
        print(f"  Error: Could not fetch metadata for {asin}: {e}")
        return None


def transform_to_libation_metadata(audible_data):
    """Transform Audible API response to Libation .metadata.json format."""

    # Authors
    authors = []
    for author in audible_data.get("authors", []):
        authors.append({
            "name": author.get("name"),
            "asin": author.get("asin"),
        })

    # Narrators
    narrators = []
    for narrator in audible_data.get("narrators", []):
        narrators.append({
            "name": narrator.get("name"),
            "asin": narrator.get("asin"),
        })

    # Series
    series = []
    for s in audible_data.get("series", []):
        series.append({
            "title": s.get("title"),
            "sequence": s.get("sequence"),
            "asin": s.get("asin"),
        })

    # Category ladders (already in correct format from API)
    category_ladders = audible_data.get("category_ladders", [])

    # Publisher summary — strip HTML
    publisher_summary = strip_html(
        audible_data.get("publisher_summary")
        or audible_data.get("merchandising_summary")
    )

    # Build LibationMetadata-compatible dict
    metadata = {
        "asin": audible_data.get("asin"),
        "title": audible_data.get("title"),
        "authors": authors,
        "narrators": narrators,
        "series": series,
        "publisher_summary": publisher_summary,
        "category_ladders": category_ladders,
        "runtime_length_min": audible_data.get("runtime_length_min"),
        "release_date": audible_data.get("release_date"),
        "publisher": audible_data.get("publisher_name"),
    }

    # Extra metadata (stored in Book.metadata JSON field)
    # These are bonus fields your import script preserves
    if audible_data.get("rating"):
        metadata["rating"] = audible_data["rating"]
    if audible_data.get("customer_reviews"):
        metadata["customer_reviews"] = audible_data["customer_reviews"]
    if audible_data.get("language"):
        metadata["language"] = audible_data["language"]
    if audible_data.get("format_type"):
        metadata["format_type"] = audible_data["format_type"]

    return metadata


def download_audio(asin, output_dir):
    """Download audiobook using audible-cli."""
    print(f"  Downloading audio for {asin}...")

    cmd = [
        "audible", "download",
        "-a", asin,
        "--aaxc",                   # New format (better quality)
        "--cover",                  # Download cover art
        "--cover-size", "1215",     # High-res cover
        "--chapter",                # Download chapter metadata
        "--output-dir", str(output_dir),
        "--filename-mode", "ascii",
    ]

    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        print(f"  Error downloading: {result.stderr}")
        # Try AAX fallback
        print(f"  Retrying with AAX format...")
        cmd_aax = [
            "audible", "download",
            "-a", asin,
            "--aax-fallback",
            "--cover",
            "--cover-size", "1215",
            "--chapter",
            "--output-dir", str(output_dir),
            "--filename-mode", "ascii",
        ]
        result = subprocess.run(cmd_aax, capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(f"Download failed: {result.stderr}")

    print(f"  Download complete.")


def convert_to_m4b(output_dir):
    """Convert AAXC/AAX to M4B if needed using ffmpeg."""
    aaxc_files = list(output_dir.glob("*.aaxc"))
    aax_files = list(output_dir.glob("*.aax"))

    for aaxc in aaxc_files:
        m4b_path = aaxc.with_suffix(".m4b")
        if m4b_path.exists():
            continue

        print(f"  Converting {aaxc.name} → {m4b_path.name}...")

        # Get voucher file for decryption key
        voucher = aaxc.with_suffix(".voucher")
        if not voucher.exists():
            print(f"  Warning: No voucher file found for {aaxc.name}")
            continue

        # Read decryption keys from voucher
        with open(voucher) as f:
            voucher_data = json.load(f)

        key = voucher_data.get("content_license", {}).get(
            "license_response", {}
        ).get("key")
        iv = voucher_data.get("content_license", {}).get(
            "license_response", {}
        ).get("iv")

        if key and iv:
            cmd = [
                "ffmpeg", "-y",
                "-audible_key", key,
                "-audible_iv", iv,
                "-i", str(aaxc),
                "-c", "copy",
                str(m4b_path),
            ]
        else:
            # Try without explicit keys (ffmpeg may handle it)
            cmd = [
                "ffmpeg", "-y",
                "-i", str(aaxc),
                "-c", "copy",
                str(m4b_path),
            ]

        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"  Warning: Conversion failed: {result.stderr[:200]}")
        else:
            # Clean up source file
            aaxc.unlink()
            if voucher.exists():
                voucher.unlink()

    # Handle AAX files similarly
    for aax in aax_files:
        m4b_path = aax.with_suffix(".m4b")
        if m4b_path.exists():
            continue

        print(f"  Converting {aax.name} → {m4b_path.name}...")
        cmd = [
            "ffmpeg", "-y",
            "-i", str(aax),
            "-c", "copy",
            str(m4b_path),
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            aax.unlink()


def organize_files(temp_dir, output_dir, asin, title):
    """
    Move downloaded files from temp dir to Libation-compatible folder structure.

    Target: {output_dir}/{Title} [{ASIN}]/
              ├── {Title} [{ASIN}].m4b
              ├── {Title} [{ASIN}].jpg
              └── {Title} [{ASIN}].metadata.json
    """
    safe_title = sanitize_filename(title)
    folder_name = f"{safe_title} [{asin}]"
    book_dir = output_dir / folder_name
    book_dir.mkdir(parents=True, exist_ok=True)

    # Move and rename files
    for f in temp_dir.iterdir():
        if f.suffix == ".m4b":
            dest = book_dir / f"{folder_name}.m4b"
        elif f.suffix == ".mp3":
            dest = book_dir / f"{folder_name}.mp3"
        elif f.suffix == ".jpg":
            dest = book_dir / f"{folder_name}.jpg"
        elif f.name.endswith(".metadata.json"):
            dest = book_dir / f"{folder_name}.metadata.json"
        elif f.suffix == ".json":
            # Chapter file — keep original name for reference
            dest = book_dir / f.name
        else:
            continue

        f.rename(dest)

    return book_dir


def upload_to_s3(book_dir, s3_bucket=S3_BUCKET):
    """Upload book folder to S3."""
    folder_name = book_dir.name
    print(f"  Uploading to s3://{s3_bucket}/{folder_name}/...")

    cmd = [
        "aws", "s3", "sync",
        str(book_dir),
        f"s3://{s3_bucket}/{folder_name}/",
        "--exclude", "*.cue",
        "--exclude", "*.voucher",
        "--exclude", ".DS_Store",
        "--profile", AWS_PROFILE,
        "--region", "us-east-1",
    ]

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"S3 upload failed: {result.stderr}")

    print(f"  Upload complete.")


def run_import():
    """Run the Book Vault import script to register in database."""
    print("  Running database import...")

    # Assumes you're in the book-vault project directory
    result = subprocess.run(
        ["npm", "run", "import"],
        capture_output=True,
        text=True,
        cwd=os.environ.get("BOOK_VAULT_DIR", os.getcwd()),
    )

    if result.returncode != 0:
        print(f"  Warning: Import had issues: {result.stderr[:500]}")
    else:
        print(f"  Import complete.")


def get_new_books_since_last_run(client):
    """Find books purchased since last script run."""
    # Read last run timestamp
    last_run = None
    if os.path.exists(LAST_RUN_FILE):
        with open(LAST_RUN_FILE) as f:
            last_run = f.read().strip()

    if not last_run:
        # Default to 30 days ago
        from datetime import timedelta
        last_run = (datetime.utcnow() - timedelta(days=30)).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        )

    print(f"Looking for books purchased after {last_run}...")

    library = client.get(
        "1.0/library",
        response_groups=RESPONSE_GROUPS,
        purchased_after=last_run,
        sort_by="-PurchaseDate",
        num_results=50,
    )

    items = library.get("items", [])
    print(f"Found {len(items)} new book(s).")
    return items


def save_last_run():
    """Save current timestamp as last run."""
    os.makedirs(os.path.dirname(LAST_RUN_FILE), exist_ok=True)
    with open(LAST_RUN_FILE, "w") as f:
        f.write(datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"))


def list_library(client):
    """List all books in Audible library."""
    library = client.get(
        "1.0/library",
        response_groups="product_attrs,contributors,series",
        sort_by="-PurchaseDate",
        num_results=50,
    )

    for item in library.get("items", []):
        authors = ", ".join(a["name"] for a in item.get("authors", []))
        series_info = ""
        if item.get("series"):
            s = item["series"][0]
            series_info = f" [{s['title']} #{s.get('sequence', '?')}]"

        print(f"  {item['asin']}  {item['title']}{series_info}  —  {authors}")


def process_book(client, asin, output_dir, skip_s3=False, skip_import=False):
    """Full pipeline for a single book."""
    print(f"\n{'='*60}")
    print(f"Processing: {asin}")
    print(f"{'='*60}")

    # 1. Fetch metadata from Audible API
    audible_data = fetch_book_metadata(client, asin)
    if not audible_data:
        print(f"  FAILED: Could not fetch metadata for {asin}")
        return False

    title = audible_data.get("title", "Unknown")
    print(f"  Title: {title}")

    # 2. Check if already downloaded
    safe_title = sanitize_filename(title)
    folder_name = f"{safe_title} [{asin}]"
    final_dir = output_dir / folder_name
    if final_dir.exists() and any(final_dir.glob("*.m4b")) or any(final_dir.glob("*.mp3")):
        print(f"  Already downloaded at {final_dir}")
        return True

    # 3. Transform metadata to Libation format
    metadata = transform_to_libation_metadata(audible_data)

    # 4. Download audio + cover + chapters to temp dir
    import tempfile
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_path = Path(temp_dir)

        try:
            download_audio(asin, temp_path)
        except RuntimeError as e:
            print(f"  FAILED: {e}")
            return False

        # 5. Convert AAXC/AAX to M4B
        convert_to_m4b(temp_path)

        # 6. Save metadata.json
        metadata_path = temp_path / f"{folder_name}.metadata.json"
        with open(metadata_path, "w") as f:
            json.dump(metadata, f, indent=2, default=str)

        # 7. Organize into Libation folder structure
        book_dir = organize_files(temp_path, output_dir, asin, title)

    print(f"  Saved to: {book_dir}")

    # 8. Upload to S3
    if not skip_s3:
        try:
            upload_to_s3(book_dir)
        except RuntimeError as e:
            print(f"  S3 upload failed: {e}")
            print(f"  Files are saved locally. Upload manually later.")

    # 9. Run database import
    if not skip_import:
        run_import()

    return True


def main():
    parser = argparse.ArgumentParser(
        description="Download audiobooks from Audible to Book Vault"
    )

    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument(
        "--asin", "-a",
        help="Download a specific book by ASIN"
    )
    group.add_argument(
        "--new", "-n",
        action="store_true",
        help="Download all books purchased since last run"
    )
    group.add_argument(
        "--list", "-l",
        action="store_true",
        help="List recent books in your Audible library"
    )

    parser.add_argument(
        "--output-dir", "-o",
        default=DEFAULT_OUTPUT_DIR,
        help=f"Local output directory (default: {DEFAULT_OUTPUT_DIR})"
    )
    parser.add_argument(
        "--skip-s3",
        action="store_true",
        help="Skip S3 upload (save locally only)"
    )
    parser.add_argument(
        "--skip-import",
        action="store_true",
        help="Skip database import step"
    )

    args = parser.parse_args()
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    # Initialize Audible client
    client = get_audible_client()

    if args.list:
        print("Recent books in your Audible library:\n")
        list_library(client)
        return

    if args.asin:
        success = process_book(
            client, args.asin, output_dir,
            skip_s3=args.skip_s3,
            skip_import=args.skip_import,
        )
        sys.exit(0 if success else 1)

    if args.new:
        items = get_new_books_since_last_run(client)
        if not items:
            print("No new books to download.")
            return

        results = {"success": 0, "failed": 0}
        for item in items:
            success = process_book(
                client, item["asin"], output_dir,
                skip_s3=args.skip_s3,
                skip_import=args.skip_import,
            )
            results["success" if success else "failed"] += 1

        save_last_run()

        print(f"\n{'='*60}")
        print(f"Batch complete: {results['success']} succeeded, "
              f"{results['failed']} failed")
        print(f"{'='*60}")


if __name__ == "__main__":
    main()
```

---

### Phase 3: Testing & Validation

**Time estimate**: 1-2 hours

#### Test 1: List library

```bash
python scripts/audible-download.py --list
```

Should show your recent Audible purchases with ASINs, titles, and authors.

#### Test 2: Download single book (local only)

```bash
python scripts/audible-download.py --asin B0XXXXXXXX --skip-s3 --skip-import
```

Verify:

- Folder created: `~/Audiobooks/Book Title [B0XXXXXXXX]/`
- Files present: `.m4b`, `.jpg`, `.metadata.json`
- `.metadata.json` has correct Libation format (compare with existing Libation output)

#### Test 3: Compare metadata with Libation

Pick a book you've already downloaded with Libation. Run the script for the same ASIN and diff the metadata:

```bash
diff ~/Audiobooks/Book\ Title\ [ASIN]/*.metadata.json \
     /Volumes/BeeDrive/Libation/Book\ Title\ [ASIN]/*.metadata.json
```

Fields should match. Minor differences (ordering, extra fields) are fine — `import-libation.ts` only reads the fields it needs.

#### Test 4: Full pipeline (download → S3 → import)

```bash
python scripts/audible-download.py --asin B0XXXXXXXX
```

Verify:

- Files uploaded to `s3://book-vault-media/Book Title [ASIN]/`
- Book appears in Book Vault web UI
- Metadata correct (authors, narrators, series, cover image)
- Audio plays

#### Test 5: Batch download

```bash
# Buy or add a new book on Audible, then:
python scripts/audible-download.py --new
```

---

## Configuration

### Environment Variables

```bash
# Where to save downloaded audiobooks locally
AUDIBLE_OUTPUT_DIR=~/Audiobooks

# S3 bucket for Book Vault media
AWS_S3_BUCKET=book-vault-media

# AWS CLI profile
AWS_PROFILE=book_vault

# Book Vault project directory (for npm run import)
BOOK_VAULT_DIR=/path/to/book_vault
```

### Optional: Add to package.json

```json
{
  "scripts": {
    "audible:list": "python scripts/audible-download.py --list",
    "audible:download": "python scripts/audible-download.py --asin",
    "audible:new": "python scripts/audible-download.py --new"
  }
}
```

---

## Edge Cases & Notes

### DRM Handling

`audible-cli` handles DRM removal during download when using `--aaxc` format. The AAXC files come with a `.voucher` file containing decryption keys. `ffmpeg` (4.4+) can use these keys to convert to standard M4B. If conversion fails, the script falls back to AAX format which some `ffmpeg` builds can handle with activation bytes.

### Multi-Part Books

Some longer audiobooks on Audible are split into multiple parts (Part 1, Part 2, etc.). The Audible API exposes these via `response_groups=relationships` with `child_asin` fields. The script should detect and download all parts. This is a V2 enhancement — for now, the script handles single-part books which covers the vast majority.

### Already Downloaded Books

The script checks if the output folder already contains an audio file before downloading. Running it multiple times for the same ASIN is safe — it will skip already-downloaded books.

### Authentication Refresh

The `audible` Python library handles token refresh automatically. The auth file at `~/.audible/auth.json` is updated in place when tokens expire. If authentication fails, re-run `audible quickstart`.

### Rate Limiting

The Audible API has undocumented rate limits. For batch downloads (`--new`), the script processes books sequentially with natural pauses (download time). Don't add explicit parallelism.

---

## Implementation Checklist

### Phase 1: Setup (1 hour)

- [ ] Install `audible-cli` via pip/uv
- [ ] Run `audible quickstart` to authenticate
- [ ] Verify `audible library list` works
- [ ] Install `ffmpeg` if not present (`brew install ffmpeg`)
- [ ] Install `boto3` (`pip install boto3`)

### Phase 2: Script Development (4-6 hours)

- [ ] Create `scripts/audible-download.py`
- [ ] Implement `fetch_book_metadata()` — Audible API call
- [ ] Implement `transform_to_libation_metadata()` — field mapping
- [ ] Implement `download_audio()` — audible-cli wrapper
- [ ] Implement `convert_to_m4b()` — ffmpeg conversion
- [ ] Implement `organize_files()` — Libation folder structure
- [ ] Implement `upload_to_s3()` — aws s3 sync
- [ ] Implement `run_import()` — npm run import trigger
- [ ] Implement `--new` batch mode with last-run tracking
- [ ] Implement `--list` for browsing library

### Phase 3: Testing (1-2 hours)

- [ ] Test `--list` shows library
- [ ] Test single book download (local only)
- [ ] Compare metadata output with existing Libation files
- [ ] Test full pipeline (download → S3 → import → play)
- [ ] Test batch mode with `--new`
- [ ] Test skip flags (`--skip-s3`, `--skip-import`)

### Post-Implementation

- [ ] Add npm scripts for convenience
- [ ] Document in README.md
- [ ] Add to CLAUDE.md (scripts reference)

---

## V2 Enhancements

1. **Multi-part book support**: Detect and download all parts of split audiobooks via `relationships` response group
2. **Progress bar**: Add `tqdm` for download progress visualization
3. **Dry run mode**: `--dry-run` to show what would be downloaded without doing it
4. **Config file**: Move settings out of env vars into a YAML/TOML config
5. **Parallel S3 upload**: Use `boto3` transfer manager for faster uploads of large files
6. **Webhook/notification**: POST to Book Vault API when new book is ready (instead of full import re-run)
7. **Watch mode**: Poll Audible library every N hours for new purchases (could run as cron)
8. **Direct API import**: Instead of `npm run import`, call the Book Vault API directly to register the book — skips the full library scan

---

## Cost

Zero additional AWS cost. S3 upload uses your existing bucket and `aws s3 sync`. The `audible` library and `audible-cli` are free and open source. The only cost is the Audible membership you already have.

---

## Related Documents

- [scripts/import-libation.ts](../scripts/import-libation.ts) — Existing import script this feeds into
- [docs/media-configuration.md](../docs/media-configuration.md) — S3 and media path configuration
- [docs/architecture.md](../docs/architecture.md) — Import workflow documentation

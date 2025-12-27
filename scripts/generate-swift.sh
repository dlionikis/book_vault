#!/bin/bash
set -e

echo "🔄 Generating Swift models from OpenAPI spec..."

# Configuration
SPEC_PATH="docs/api/openapi.yaml"
OUTPUT_DIR="ios/BookVault/Generated/Models"
TEMPLATE_DIR="scripts/swift-templates"

# Validate spec exists
if [ ! -f "$SPEC_PATH" ]; then
  echo "❌ Error: OpenAPI spec not found at $SPEC_PATH"
  exit 1
fi

# Validate iOS project exists
if [ ! -d "ios/BookVault" ]; then
  echo "❌ Error: iOS project not found at ios/BookVault"
  exit 1
fi

# Clean previous generation
echo "🗑️  Cleaning previous generated code..."
rm -rf "$OUTPUT_DIR"/*
mkdir -p "$OUTPUT_DIR"

# Generate Swift models
echo "📝 Generating Swift models..."
openapi-generator generate \
  -i "$SPEC_PATH" \
  -g swift5 \
  -o "$OUTPUT_DIR" \
  --additional-properties=projectName=BookVault \
  --additional-properties=responseAs=AsyncAwait \
  --additional-properties=library=urlsession \
  --additional-properties=swiftPackageManager=false \
  --skip-validate-spec

# Move generated models to a flatter structure and clean up
echo "🧹 Reorganizing generated files..."
if [ -d "$OUTPUT_DIR/BookVault/Classes/OpenAPIs" ]; then
  # Move Models.swift to the top level
  if [ -f "$OUTPUT_DIR/BookVault/Classes/OpenAPIs/Models.swift" ]; then
    mv "$OUTPUT_DIR/BookVault/Classes/OpenAPIs/Models.swift" "$OUTPUT_DIR/"
  fi
  # Move individual model files if they exist
  if [ -d "$OUTPUT_DIR/BookVault/Classes/OpenAPIs/Models" ]; then
    find "$OUTPUT_DIR/BookVault/Classes/OpenAPIs/Models" -name "*.swift" -exec mv {} "$OUTPUT_DIR/" \;
  fi
  # Remove the nested directory structure
  rm -rf "$OUTPUT_DIR/BookVault"
fi
# Remove documentation and generator metadata
rm -rf "$OUTPUT_DIR/docs" "$OUTPUT_DIR/.openapi-generator"

# Format generated code (if swiftformat is available)
if command -v swiftformat &> /dev/null; then
  echo "✨ Formatting generated code..."
  swiftformat "$OUTPUT_DIR" --swiftversion 5.9
fi

echo "✅ Swift models generated successfully at $OUTPUT_DIR"
echo ""
echo "Generated files:"
ls -lh "$OUTPUT_DIR"/*.swift 2>/dev/null || echo "  (none yet - run after creating OpenAPI spec)"

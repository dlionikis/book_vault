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

# Validate template overrides exist. These are not optional:
#   Validation.mustache — adds Sendable conformance to the rule structs (A3).
#   Models.mustache     — drops the request-layer declarations, including
#                         RequestTask, which references URLSessionDataTaskProtocol
#                         from the request layer we no longer generate (Plan C).
#   Extensions.mustache — drops the one HTTPURLResponse extension that reads
#                         Configuration.successfulStatusCodeRange (Plan C).
# Without these, the generated code does not compile.
for tmpl in Validation Models Extensions; do
  if [ ! -f "$TEMPLATE_DIR/$tmpl.mustache" ]; then
    echo "❌ Error: template override missing at $TEMPLATE_DIR/$tmpl.mustache"
    echo "   Generated code would not compile under Swift 6."
    echo "   See docs/archive/completed-plans/ios-swift6-generated-networking-plan.md."
    exit 1
  fi
done

# Clean previous generation (preserve committed files like Models.swift)
echo "🗑️  Cleaning previous generated code..."
# Keep the committed Models.swift if it exists (has custom validation types)
if [ -f "$OUTPUT_DIR/Models.swift" ]; then
  cp "$OUTPUT_DIR/Models.swift" /tmp/Models.swift.backup
fi
rm -rf "$OUTPUT_DIR"/*
mkdir -p "$OUTPUT_DIR"

# Determine which openapi-generator command to use
# CI uses openapi-generator-cli (npm package), local may use openapi-generator (brew)
if command -v openapi-generator-cli &> /dev/null; then
  OPENAPI_GEN="openapi-generator-cli"
elif command -v openapi-generator &> /dev/null; then
  OPENAPI_GEN="openapi-generator"
else
  echo "❌ Error: openapi-generator not found. Install with:"
  echo "   brew install openapi-generator  # macOS"
  echo "   npm install -g @openapitools/openapi-generator-cli  # npm"
  exit 1
fi

# Support files to emit. This is an explicit ALLOWLIST, not a filter: everything
# not named here is never generated.
#
# Only three files survive, and only because the model files genuinely need them:
#   Models.swift      — declares JSONEncodable (every model conforms) and
#                       CaseIterableDefaultsLast (enum models use it)
#   Validation.swift  — NumericRule / StringRule, held as `static let` by 24 models
#   Extensions.swift  — the encode/decode helpers the model bodies call
#
# Everything else the generator offers belongs to the request-execution layer and
# is unreachable here: the app's networking is the hand-written APIClient talking
# to URLSession directly. Omitted deliberately, each verified to have zero
# references from app, test, or model code:
#   URLSessionImplementations.swift, APIs.swift, Configuration.swift  (request layer)
#   CodableHelper.swift, JSONEncodingHelper.swift, JSONDataEncoding.swift,
#   APIHelper.swift, OpenISO8601DateFormatter.swift                   (its helpers)
#
# That whole cluster was what blocked the Swift 6 language mode -- CodableHelper
# alone contributed 6 "nonisolated global shared mutable state" errors.
#
# If a future spec change makes the generator want a new support file, the build
# fails loudly on a missing symbol rather than silently regressing. Add it here
# only after confirming it is genuinely needed.
# See docs/archive/completed-plans/ios-swift6-generated-networking-plan.md.
SUPPORTING_FILES="Models.swift:Validation.swift:Extensions.swift"

# Generate Swift models
echo "📝 Generating Swift models..."
$OPENAPI_GEN generate \
  -i "$SPEC_PATH" \
  -g swift5 \
  -o "$OUTPUT_DIR" \
  -t "$TEMPLATE_DIR" \
  --additional-properties=projectName=BookVault \
  --additional-properties=responseAs=AsyncAwait \
  --additional-properties=library=urlsession \
  --additional-properties=swiftPackageManager=false \
  --global-property="models,modelDocs=false,apis=false,supportingFiles=$SUPPORTING_FILES" \
  --skip-validate-spec

# Move generated models to a flatter structure and clean up
echo "🧹 Reorganizing generated files..."
if [ -d "$OUTPUT_DIR/BookVault/Classes/OpenAPIs" ]; then
  # Move all supporting Swift files (Models.swift, Validation.swift, etc.) to the top level
  find "$OUTPUT_DIR/BookVault/Classes/OpenAPIs" -maxdepth 1 -name "*.swift" -exec mv {} "$OUTPUT_DIR/" \;

  # Move individual model files if they exist
  if [ -d "$OUTPUT_DIR/BookVault/Classes/OpenAPIs/Models" ]; then
    find "$OUTPUT_DIR/BookVault/Classes/OpenAPIs/Models" -name "*.swift" -exec mv {} "$OUTPUT_DIR/" \;
  fi

  # Remove the nested directory structure
  rm -rf "$OUTPUT_DIR/BookVault"
fi

# Restore the committed Models.swift which has custom validation types
# (The generated Validation.swift provides these types, so we prefer it when available)
if [ -f "$OUTPUT_DIR/Validation.swift" ]; then
  echo "✅ Using generated Validation.swift for validation types"
  # Don't need to restore backup since Validation.swift provides the types
  rm -f /tmp/Models.swift.backup
elif [ -f /tmp/Models.swift.backup ]; then
  echo "⚠️  Restoring custom Models.swift (no Validation.swift generated)"
  mv /tmp/Models.swift.backup "$OUTPUT_DIR/Models.swift"
fi
# Remove documentation, generator metadata, and boilerplate non-Swift files
rm -rf "$OUTPUT_DIR/docs" "$OUTPUT_DIR/.openapi-generator"
rm -f "$OUTPUT_DIR/git_push.sh" "$OUTPUT_DIR/BookVault.podspec" "$OUTPUT_DIR/Cartfile" "$OUTPUT_DIR/README.md" "$OUTPUT_DIR/.openapi-generator-ignore" "$OUTPUT_DIR/.swiftformat"

# Format generated code (if swiftformat is available)
if command -v swiftformat &> /dev/null; then
  echo "✨ Formatting generated code..."
  swiftformat "$OUTPUT_DIR" --swiftversion 5.9
fi

echo "✅ Swift models generated successfully at $OUTPUT_DIR"
echo ""
echo "Generated files:"
ls -lh "$OUTPUT_DIR"/*.swift 2>/dev/null || echo "  (none yet - run after creating OpenAPI spec)"

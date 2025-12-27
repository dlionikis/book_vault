#!/bin/bash
# Script to add Swift files to Xcode project using sed

PROJECT_FILE="BookVault.xcodeproj/project.pbxproj"

# Backup the project file
cp "$PROJECT_FILE" "$PROJECT_FILE.backup"

# Read the project file
CONTENT=$(cat "$PROJECT_FILE")

# Generate UUIDs for each file
UUID_API=$(uuidgen | tr -d '-' | tr '[:lower:]' '[:upper:]' | cut -c1-24)
UUID_AUTH=$(uuidgen | tr -d '-' | tr '[:lower:]' '[:upper:]' | cut -c1-24)
UUID_LOGIN=$(uuidgen | tr -d '-' | tr '[:lower:]' '[:upper:]' | cut -c1-24)
UUID_BOOKS=$(uuidgen | tr -d '-' | tr '[:lower:]' '[:upper:]' | cut -c1-24)
UUID_DETAIL=$(uuidgen | tr -d '-' | tr '[:lower:]' '[:upper:]' | cut -c1-24)

UUID_API_BUILD=$(uuidgen | tr -d '-' | tr '[:lower:]' '[:upper:]' | cut -c1-24)
UUID_AUTH_BUILD=$(uuidgen | tr -d '-' | tr '[:lower:]' '[:upper:]' | cut -c1-24)
UUID_LOGIN_BUILD=$(uuidgen | tr -d '-' | tr '[:lower:]' '[:upper:]' | cut -c1-24)
UUID_BOOKS_BUILD=$(uuidgen | tr -d '-' | tr '[:lower:]' '[:upper:]' | cut -c1-24)
UUID_DETAIL_BUILD=$(uuidgen | tr -d '-' | tr '[:lower:]' '[:upper:]' | cut -c1-24)

echo "Generated UUIDs for files..."

# Find PBXBuildFile section and add references
# Find PBXFileReference section and add file references  
# Find PBXSourcesBuildPhase and add to sources

echo "Please add the files manually in Xcode or use xcodeproj Ruby gem."
echo "Alternatively, opening the project in Xcode and adding the files will work."


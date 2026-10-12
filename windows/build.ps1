#!/usr/bin/env bash
# Textractor Windows Build Script
# Produces a standalone Windows .exe installer

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${ROOT}/Textractor.Windows"
CONFIG="Release"

echo "▸ Building Textractor.Windows (${CONFIG})..."

# Restore NuGet packages
dotnet restore "${PROJECT_DIR}/Textractor.Windows.csproj"

# Build the project
dotnet build "${PROJECT_DIR}/Textractor.Windows.csproj" -c "${CONFIG}" --no-restore

# Publish as self-contained single-file executable
dotnet publish "${PROJECT_DIR}/Textractor.Windows.csproj" \
    -c "${CONFIG}" \
    -r win-x64 \
    --self-contained true \
    -p:PublishSingleFile=true \
    -p:IncludeNativeLibrariesForSelfExtract=true \
    -p:EnableCompressionInSingleFile=true \
    -p:PublishTrimmed=true \
    -p:TrimMode=partial \
    -o "${ROOT}/dist/win-x64"

# Copy resources
echo "▸ Copying resources..."
mkdir -p "${ROOT}/dist/win-x64/Resources"
cp "${PROJECT_DIR}/Resources/textractor-splash.png" "${ROOT}/dist/win-x64/Resources/" 2>/dev/null || true
cp "${PROJECT_DIR}/Resources/textractor-type.png" "${ROOT}/dist/win-x64/Resources/" 2>/dev/null || true
cp "${PROJECT_DIR}/Resources/textractor.ico" "${ROOT}/dist/win-x64/Resources/" 2>/dev/null || true

# Copy Tesseract data files
echo "▸ Setting up Tesseract data..."
mkdir -p "${ROOT}/dist/win-x64/tessdata"
# In production: download or copy tessdata files here
# For now, create a placeholder
echo "Tesseract data files should be placed here" > "${ROOT}/dist/win-x64/tessdata/README.txt"

echo ""
echo "✓ Built successfully at ${ROOT}/dist/win-x64/Textractor.Windows.exe"
echo ""
echo "To create installer, run:"
echo "  iscc ${ROOT}/installer.iss"
echo ""
echo "Or run directly:"
echo "  ${ROOT}/dist/win-x64/Textractor.Windows.exe"
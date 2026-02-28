#!/bin/bash
# Release build script for AsciiSourcerer gem

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PROJECT_NAME="asciisourcerer"
GEMSPEC_FILE="${PROJECT_NAME}.gemspec"

echo -e "${GREEN}🚀 ${PROJECT_NAME} Release Build Script${NC}"
echo "=================================="

# Validation
if [ ! -f "$GEMSPEC_FILE" ]; then
    echo -e "${RED}❌ Error: $GEMSPEC_FILE not found. Run this script from the project root.${NC}"
    exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
    echo -e "${RED}❌ Error: Working directory is not clean. Commit or stash changes first.${NC}"
    git status --short
    exit 1
fi

current_branch=$(git branch --show-current)
if [ "$current_branch" != "main" ]; then
    echo -e "${YELLOW}⚠️  Warning: Not on main branch (currently on: $current_branch)${NC}"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
fi

if ! bundle check > /dev/null 2>&1; then
    echo -e "${YELLOW}📦 Installing gem dependencies...${NC}"
    bundle install
fi

# Run tests
echo -e "${YELLOW}🧪 Running tests...${NC}"
bundle exec rake pr_test
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Tests failed. Fix tests before releasing.${NC}"
    exit 1
fi

# Get current version using Asciidoctor to resolve attributes
current_version=$(ruby -r asciidoctor -e "doc = Asciidoctor.load_file('README.adoc', safe: :unsafe); puts doc.attributes['this_prod_vrsn']")
echo -e "${GREEN}📋 Current version: $current_version${NC}"

# Build gem
echo -e "${YELLOW}🔨 Building gem...${NC}"
mkdir -p pkg/
gem build "$GEMSPEC_FILE"
mv "${PROJECT_NAME}"-*.gem pkg/

# Test built gem
echo -e "${YELLOW}🧪 Testing built gem...${NC}"
gem_file=$(ls pkg/"${PROJECT_NAME}"-*.gem | sort -V | tail -n1)
echo "Testing gem file: $gem_file"

# Test gem installation in clean Docker environment
echo "Testing gem installation in clean environment (Docker)..."
if command -v docker &> /dev/null; then
    docker run --rm -v "$(pwd)/pkg:/gems" ruby:3.2 bash -c "
        gem install /gems/$(basename "$gem_file") --no-document > /dev/null 2>&1
        if [ \$? -ne 0 ]; then
            echo 'ERROR: Gem installation failed'
            exit 1
        fi
        
        actual_version=\$(ruby -e \"require 'asciisourcerer'; puts Sourcerer::VERSION\")
        echo \"Installed version: \$actual_version\"
        
        if [ \"\$actual_version\" != \"$current_version\" ]; then
            echo \"ERROR: Version mismatch! Expected: $current_version, Got: \$actual_version\"
            exit 1
        fi
        
        echo '✅ Gem installation and version check passed'
    "
else
    echo -e "${YELLOW}⚠️  Docker not available, skipping containerized gem test${NC}"
fi

echo ""
echo -e "${GREEN}✅ Build completed successfully!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Version: $current_version${NC}"
echo -e "${GREEN}Gem: $gem_file${NC}"
echo ""
echo "Next steps:"
echo "  1. Review the built artifacts"
echo "  2. Run ./scripts/publish.sh to publish to RubyGems"

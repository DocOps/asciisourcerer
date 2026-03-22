#!/usr/bin/env bash
# Publishing script for AsciiSourcerer gem

set -e

# Parse command line arguments
DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--dry-run]"
      exit 1
      ;;
  esac
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PROJECT_NAME="asciisourcerer"

echo -e "${GREEN}📦 ${PROJECT_NAME} Publishing Script${NC}"
echo "=============================="

# Check for required environment variables (skip in dry-run mode)
if [ "$DRY_RUN" = false ]; then
    if [ -z "$RUBYGEMS_API_KEY" ]; then
        echo -e "${RED}❌ Error: RUBYGEMS_API_KEY environment variable not set${NC}"
        echo "Get your API key from https://rubygems.org/profile/edit"
        echo "Then run: export RUBYGEMS_API_KEY=your_key_here"
        exit 1
    fi
fi

# Get current version using Asciidoctor to resolve attributes
current_version=$(ruby -r asciidoctor -e "doc = Asciidoctor.load_file('README.adoc', safe: :unsafe); puts doc.attributes['this_prod_vrsn']")
gem_file="pkg/${PROJECT_NAME}-$current_version.gem"

# Check if gem file exists
if [ ! -f "$gem_file" ]; then
    echo -e "${RED}❌ Error: Gem file $gem_file not found${NC}"
    echo "Run ./scripts/build.sh first"
    exit 1
fi

if [ "$DRY_RUN" = true ]; then
  echo -e "${YELLOW}🔍 Dry run mode enabled. The following actions would be performed:${NC}"
  echo "- Publish to RubyGems: gem push $gem_file"
  echo ""
  echo "Gem file ready: $gem_file"
else
  # Publish to RubyGems
  echo -e "${YELLOW}💎 Publishing to RubyGems...${NC}"
  mkdir -p ~/.gem
  echo ":rubygems_api_key: $RUBYGEMS_API_KEY" > ~/.gem/credentials
  chmod 0600 ~/.gem/credentials
  gem push "$gem_file"
  echo -e "${GREEN}✅ Published to RubyGems successfully${NC}"
  
  echo ""
  echo -e "${GREEN}✅ Publication completed!${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}Version: $current_version${NC}"
  echo -e "${GREEN}RubyGems: https://rubygems.org/gems/${PROJECT_NAME}${NC}"
fi

#!/usr/bin/env bash
set -euo pipefail

# MouthType Release Script
# Usage: ./scripts/release.sh [major|minor|patch]

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MouthType"

# Get current version from git tags
get_current_version() {
    local latest_tag
    latest_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
    echo "${latest_tag#v}"
}

# Bump version
bump_version() {
    local current="$1"
    local type="$2"
    
    local major minor patch
    major=$(echo "$current" | cut -d. -f1)
    minor=$(echo "$current" | cut -d. -f2)
    patch=$(echo "$current" | cut -d. -f3)
    
    case "$type" in
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        patch)
            patch=$((patch + 1))
            ;;
        *)
            echo "Invalid bump type: $type"
            exit 1
            ;;
    esac
    
    echo "${major}.${minor}.${patch}"
}

# Update CHANGELOG
update_changelog() {
    local version="$1"
    local date
    date=$(date +%Y-%m-%d)
    
    # Create temp file
    local temp_file
    temp_file=$(mktemp)
    
    # Add new version section after the Unreleased section
    awk -v ver="$version" -v dt="$date" '
        /^## \[Unreleased\]/ {
            print
            print ""
            print "## [" ver "] - " dt
            next
        }
        { print }
    ' CHANGELOG.md > "$temp_file"
    
    mv "$temp_file" CHANGELOG.md
}

# Main
main() {
    cd "$ROOT_DIR"
    
    # Check if we're in a git repo
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not a git repository"
        exit 1
    fi
    
    # Check for uncommitted changes
    if ! git diff-index --quiet HEAD --; then
        echo "Error: You have uncommitted changes. Please commit or stash them first."
        exit 1
    fi
    
    # Get bump type
    local bump_type="${1:-patch}"
    if [[ ! "$bump_type" =~ ^(major|minor|patch)$ ]]; then
        echo "Usage: $0 [major|minor|patch]"
        echo "  major - Breaking changes"
        echo "  minor - New features"
        echo "  patch - Bug fixes"
        exit 1
    fi
    
    # Calculate new version
    local current_version
    current_version=$(get_current_version)
    local new_version
    new_version=$(bump_version "$current_version" "$bump_type")
    
    echo "Current version: $current_version"
    echo "New version: $new_version"
    echo "Bump type: $bump_type"
    echo ""
    
    # Confirm
    read -rp "Continue? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted"
        exit 0
    fi
    
    # Update CHANGELOG
    if [ -f CHANGELOG.md ]; then
        update_changelog "$new_version"
        git add CHANGELOG.md
    fi
    
    # Commit version bump
    git commit -m "chore: bump version to ${new_version} / Bump version to ${new_version}"
    
    # Create tag
    git tag -a "v${new_version}" -m "Release v${new_version}"
    
    echo ""
    echo "Version bumped to ${new_version}"
    echo "Tag created: v${new_version}"
    echo ""
    echo "To push the release:"
    echo "  git push origin main --tags"
    echo ""
    echo "This will trigger the GitHub Actions release workflow."
}

main "$@"

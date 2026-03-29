#!/usr/bin/env bash
# ABOUTME: Creates the tednaleid/homebrew-montty tap repo on GitHub and seeds it
# ABOUTME: with an initial cask file from the latest montty release.
set -euo pipefail

OWNER="tednaleid"
TAP_REPO="homebrew-montty"
MAIN_REPO="montty"

# -- Preflight checks --

if ! command -v gh &>/dev/null; then
    echo "Error: gh CLI is required. Install with: brew install gh"
    exit 1
fi

if ! gh auth status &>/dev/null; then
    echo "Error: not authenticated with gh. Run: gh auth login"
    exit 1
fi

# -- Get latest release version and DMG sha256 --

echo "Fetching latest release info..."
VERSION=$(gh release view --repo "${OWNER}/${MAIN_REPO}" --json tagName -q .tagName)
DMG_URL="https://github.com/${OWNER}/${MAIN_REPO}/releases/download/${VERSION}/montty-${VERSION}.dmg"

echo "Downloading montty-${VERSION}.dmg to compute SHA-256..."
SHA256=$(curl -sL "$DMG_URL" | shasum -a 256 | awk '{print $1}')
echo "  Version: ${VERSION}"
echo "  SHA-256: ${SHA256}"

# -- Create the tap repo --

if gh repo view "${OWNER}/${TAP_REPO}" &>/dev/null; then
    echo "Repo ${OWNER}/${TAP_REPO} already exists, skipping creation."
else
    echo "Creating ${OWNER}/${TAP_REPO}..."
    gh repo create "${OWNER}/${TAP_REPO}" --public \
        --description "Homebrew tap for Montty, a macOS terminal app"
fi

# -- Clone, populate, and push --

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

gh repo clone "${OWNER}/${TAP_REPO}" "$WORKDIR"
cd "$WORKDIR"

mkdir -p Casks

cat > Casks/montty.rb << CASK
cask "montty" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "https://github.com/${OWNER}/${MAIN_REPO}/releases/download/#{version}/montty-#{version}.dmg"
  name "Montty"
  desc "macOS terminal app with vertical tabs, splits, and session persistence"
  homepage "https://github.com/${OWNER}/${MAIN_REPO}"

  depends_on macos: ">= :tahoe"

  app "Montty.app"

  zap trash: [
    "~/Library/Application Support/montty",
    "~/Library/Preferences/com.montty.app.plist",
    "~/Library/Caches/com.montty.app",
  ]
end
CASK

cat > README.md << 'README'
# homebrew-montty

Homebrew tap for [Montty](https://github.com/tednaleid/montty), a macOS terminal app.

## Install

```bash
brew install --cask tednaleid/montty/montty
```

Or:

```bash
brew tap tednaleid/montty
brew install --cask montty
```

## Update

```bash
brew upgrade --cask montty
```
README

git add Casks/montty.rb README.md
git commit -m "Initial cask for montty ${VERSION}"
git push

echo ""
echo "Tap repo created and populated at: https://github.com/${OWNER}/${TAP_REPO}"
echo ""
echo "-- Next step: create a fine-grained Personal Access Token --"
echo ""
echo "1. Go to: https://github.com/settings/personal-access-tokens/new"
echo "2. Token name: montty-homebrew-tap"
echo "3. Repository access: Only select repositories -> ${OWNER}/${TAP_REPO}"
echo "4. Permissions: Contents -> Read and write"
echo "5. Generate the token and copy it"
echo ""
echo "Then set it as a secret on the montty repo:"
echo ""
echo "  gh secret set HOMEBREW_TAP_TOKEN --repo ${OWNER}/${MAIN_REPO}"
echo ""
echo "(Paste the token when prompted.)"

#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(pwd)"
LOG_FILE="$SCRIPT_DIR/logs.txt"
PR_LINKS_FILE="$SCRIPT_DIR/pr-links.txt"

# Initialize logs
echo "Mass repo update started at $(date)" > "$LOG_FILE"
echo "================================================" >> "$LOG_FILE"
echo "PR Links from mass repo update started at $(date)" > "$PR_LINKS_FILE"
echo "================================================" >> "$PR_LINKS_FILE"

# Check if repo list file exists
REPO_LIST_FILE="repo-list.txt"
if [[ ! -f "$REPO_LIST_FILE" ]]; then
    echo -e "${RED}Error: $REPO_LIST_FILE not found!${NC}"
    echo "Please create a file called 'repo-list.txt' with one repository name per line."
    echo "Example format:"
    echo "  my-org/repo1"
    echo "  my-org/repo2"
    exit 1
fi

# Create all-repos directory if it doesn't exist
mkdir -p all-repos

# Read repos from file
while IFS= read -r repo_name || [[ -n "$repo_name" ]]; do
    # Skip empty lines and comments
    [[ -z "$repo_name" || "$repo_name" =~ ^[[:space:]]*# ]] && continue
    
    echo -e "${YELLOW}Processing: $repo_name${NC}"
    
    repo_dir="all-repos/$(basename "$repo_name")"
    
    # Step 2: Clone repo if not present
    if [[ ! -d "$repo_dir" ]]; then
        echo "  Cloning $repo_name..."
        if ! gh repo clone "$repo_name" "$repo_dir"; then
            echo "FAILED: Could not clone $repo_name" >> "$LOG_FILE"
            echo -e "${RED}  Failed to clone $repo_name${NC}"
            continue
        fi
    fi
    
    # Step 3: CD into repo, checkout main, and pull
    cd "$repo_dir" || {
        echo "FAILED: Could not cd into $repo_dir" >> "$LOG_FILE"
        echo -e "${RED}  Failed to cd into $repo_dir${NC}"
        cd - > /dev/null
        continue
    }
    
    # Checkout main and pull
    if ! git checkout main 2>/dev/null && ! git checkout master 2>/dev/null; then
        echo "FAILED: Could not checkout main/master branch in $repo_name" >> "$LOG_FILE"
        echo -e "${RED}  Failed to checkout main/master branch${NC}"
        cd - > /dev/null
        continue
    fi
    
    if ! git pull; then
        echo "FAILED: Could not pull latest changes in $repo_name" >> "$LOG_FILE"
        echo -e "${RED}  Failed to pull latest changes${NC}"
        cd - > /dev/null
        continue
    fi
    
    # Check if turbo.json file exists
    if [[ ! -f "turbo.json" ]]; then
        echo "SKIPPED: $repo_name - Not a turbo repo (no turbo.json file found)" >> "$LOG_FILE"
        echo -e "${YELLOW}  Skipped - Not a turbo repo${NC}"
        cd - > /dev/null
        continue
    fi
    
    echo "  Found turbo repo, processing apps..."
    
    # Step 4: Check if apps/ directory exists
    if [[ ! -d "apps" ]]; then
        echo "SKIPPED: $repo_name - No apps/ directory found" >> "$LOG_FILE"
        echo -e "${YELLOW}  Skipped - No apps/ directory${NC}"
        cd - > /dev/null
        continue
    fi
    
    changes_made=false
    
    # Step 4-7: Iterate over subdirectories in apps/
    for app_dir in apps/*/; do
        [[ ! -d "$app_dir" ]] && continue
        
        app_name=$(basename "$app_dir")
        echo "    Processing app: $app_name"
        
        # Step 5: Update package.json if it exists
        if [[ -f "$app_dir/package.json" ]]; then
            if grep -q '"next": "14.2.1",' "$app_dir/package.json"; then
                echo "      Updating Next.js version in $app_name/package.json"
                sed -i 's/"next": "14.2.1",/"next": "14.2.20",/g' "$app_dir/package.json"
                changes_made=true
            else
                echo "INFO: $repo_name/$app_name - package.json exists but 'next': '14.2.1' not found (may already be updated or on different version)" >> "$LOG_FILE"
            fi
        fi
        
        # Step 6-7: Update middleware.ts if it exists
        if [[ -f "$app_dir/middleware.ts" ]]; then
            middleware_updated=false
            
            # Step 6: Make middleware function async
            if grep -q "export function middleware(request: NextRequest) {" "$app_dir/middleware.ts"; then
                echo "      Making middleware function async in $app_name/middleware.ts"
                sed -i 's/export function middleware(request: NextRequest) {/export async function middleware(request: NextRequest) {/g' "$app_dir/middleware.ts"
                middleware_updated=true
                changes_made=true
            fi
            
            # Step 7: Add await to getMiddleware call
            if grep -q "const response = getMiddleware(request);" "$app_dir/middleware.ts"; then
                echo "      Adding await to getMiddleware call in $app_name/middleware.ts"
                sed -i 's/const response = getMiddleware(request);/const response = await getMiddleware(request);/g' "$app_dir/middleware.ts"
                middleware_updated=true
                changes_made=true
            fi
            
            if [[ "$middleware_updated" == false ]]; then
                echo "INFO: $repo_name/$app_name - middleware.ts exists but expected strings not found" >> "$LOG_FILE"
            fi
        fi
    done
    
    # Step 8-9: Create branch, commit, push, and create PR if changes were made
    if [[ "$changes_made" == true ]]; then
        branch_name="chore/update-next-and-async-middleware-$(date +%Y%m%d-%H%M%S)"
        
        echo "  Creating branch: $branch_name"
        if ! git checkout -b "$branch_name"; then
            echo "FAILED: Could not create branch $branch_name in $repo_name" >> "$LOG_FILE"
            echo -e "${RED}  Failed to create branch${NC}"
            cd - > /dev/null
            continue
        fi
        
        echo "  Committing changes..."
        git add .
        if ! git commit -m "Update Next.js to 14.2.20 and make middleware async

- Updated Next.js version from 14.2.1 to 14.2.20 in package.json files
- Made middleware function async and added await to getMiddleware calls"; then
            echo "FAILED: Could not commit changes in $repo_name" >> "$LOG_FILE"
            echo -e "${RED}  Failed to commit changes${NC}"
            cd - > /dev/null
            continue
        fi
        
        echo "  Pushing branch..."
        if ! git push origin "$branch_name"; then
            echo "FAILED: Could not push branch $branch_name in $repo_name" >> "$LOG_FILE"
            echo -e "${RED}  Failed to push branch${NC}"
            cd - > /dev/null
            continue
        fi
        
        echo "  Creating PR..."
        pr_url=$(gh pr create \
            --title "Update Next.js to 14.2.20 and make middleware async" \
            --body "This PR updates:

- Next.js version from 14.2.1 to 14.2.20 in all apps
- Makes middleware functions async and adds await to getMiddleware calls

This is an automated update across multiple repositories." \
            --head "$branch_name" 2>&1)
        
        if [[ $? -eq 0 ]]; then
            echo "$repo_name: $pr_url" >> "$PR_LINKS_FILE"
            echo -e "${GREEN}  ✓ PR created successfully${NC}"
        else
            echo "FAILED: Could not create PR for $repo_name" >> "$LOG_FILE"
            echo -e "${RED}  Failed to create PR${NC}"
        fi
    else
        echo "INFO: $repo_name - No changes needed (expected strings not found)" >> "$LOG_FILE"
        echo -e "${YELLOW}  No changes needed${NC}"
    fi
    
    cd - > /dev/null
    echo ""
    
done < "$REPO_LIST_FILE"

echo -e "${GREEN}Mass update completed! Check logs.txt for errors/skips and pr-links.txt for successful PRs.${NC}"
echo ""
echo "================================================" >> "$LOG_FILE"
echo "Mass repo update completed at $(date)" >> "$LOG_FILE"
echo "================================================" >> "$PR_LINKS_FILE"
echo "Mass repo update completed at $(date)" >> "$PR_LINKS_FILE"

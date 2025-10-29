#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(pwd)"
LOG_FILE="$SCRIPT_DIR/logs.csv"
ERROR_FILE="$SCRIPT_DIR/error.csv"

BATCH_SIZE=${1:-5}
echo -e "${YELLOW}Batch size set to: $BATCH_SIZE apps${NC}"

echo "Repo,App,Status,Notes,PR Link" > "$LOG_FILE"
echo "Repo,Issue,Details" > "$ERROR_FILE"
echo -e "${GREEN}Created new logs.csv and error.csv files${NC}"

apps_fixed=0

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
    if [[ $apps_fixed -ge $BATCH_SIZE ]]; then
        echo -e "${GREEN}Batch limit of $BATCH_SIZE apps reached. Stopping.${NC}"
        break
    fi
    
    # Skip empty lines and comments
    [[ -z "$repo_name" || "$repo_name" =~ ^[[:space:]]*# ]] && continue
    
    echo -e "${YELLOW}Processing: $repo_name (Fixed: $apps_fixed/$BATCH_SIZE)${NC}"
    
    repo_dir="all-repos/$(basename "$repo_name")"
    
    # Step 2: Clone repo if not present
    if [[ ! -d "$repo_dir" ]]; then
        echo "  Cloning $repo_name..."
        if ! gh repo clone "$repo_name" "$repo_dir"; then
            echo -e "${RED}  Failed to clone $repo_name${NC}"
            echo "\"$repo_name\",\"clone-failed\",\"Could not clone repository\"" >> "$ERROR_FILE"
            continue
        fi
    fi
    
    # Step 3: CD into repo, checkout main, and pull
    cd "$repo_dir" || {
        echo -e "${RED}  Failed to cd into $repo_dir${NC}"
        echo "\"$repo_name\",\"access-failed\",\"Could not access repository directory\"" >> "$ERROR_FILE"
        cd - > /dev/null
        continue
    }
    
    # Checkout main and pull
    if ! git checkout main 2>/dev/null && ! git checkout master 2>/dev/null; then
        echo -e "${RED}  Failed to checkout main/master branch${NC}"
        echo "\"$repo_name\",\"checkout-failed\",\"Could not checkout main or master branch\"" >> "$ERROR_FILE"
        cd - > /dev/null
        continue
    fi
    
    if ! git pull; then
        echo -e "${RED}  Failed to pull latest changes${NC}"
        echo "\"$repo_name\",\"pull-failed\",\"Could not pull latest changes\"" >> "$ERROR_FILE"
        cd - > /dev/null
        continue
    fi
    
    # Check if turbo.json file exists
    if [[ ! -f "turbo.json" ]]; then
        echo -e "${YELLOW}  Skipped - Not a turbo repo${NC}"
        echo "\"$repo_name\",\"skipped\",\"Not a turbo repository (no turbo.json found)\"" >> "$ERROR_FILE"
        cd - > /dev/null
        continue
    fi
    
    echo "  Found turbo repo, processing apps..."
    
    # Step 4: Check if apps/ directory exists
    if [[ ! -d "apps" ]]; then
        echo -e "${YELLOW}  Skipped - No apps/ directory${NC}"
        echo "\"$repo_name\",\"skipped\",\"No apps/ directory found\"" >> "$ERROR_FILE"
        cd - > /dev/null
        continue
    fi
    
    changes_made=false
    pr_url=""
    
    # Step 4-7: Iterate over subdirectories in apps/
    for app_dir in apps/*/; do
        [[ ! -d "$app_dir" ]] && continue
        
        app_name=$(basename "$app_dir")
        echo "    Processing app: $app_name"
        
        package_updated=false
        middleware_updated=false
        middleware_created=false
        
        package_already_updated=false
        middleware_already_updated=false
        
        # Check if package.json already has the new version
        if [[ -f "$app_dir/package.json" ]]; then
            if grep -q '"next": "14.2.30",' "$app_dir/package.json"; then
                package_already_updated=true
            fi
        fi
        
        # Check if middleware is already async
        if [[ -f "$app_dir/middleware.ts" ]]; then
            if grep -q "export async function middleware(" "$app_dir/middleware.ts" && 
               grep -q "await getMiddleware(request)" "$app_dir/middleware.ts"; then
                middleware_already_updated=true
            fi
        fi
        
        if [[ "$package_already_updated" == true && "$middleware_already_updated" == true ]]; then
            echo "\"$repo_name\",\"$app_name\",\"completed\",\"already updated (not counted toward batch)\",\"\"" >> "$LOG_FILE"
            echo "      App already has both updates, skipping..."
            continue
        fi
        
        # Step 5: Update package.json if it exists
        if [[ -f "$app_dir/package.json" ]]; then
            if grep -q '"next": "14.2.1",' "$app_dir/package.json"; then
                echo "      Updating Next.js version in $app_name/package.json"
                sed -i 's/"next": "14.2.1",/"next": "14.2.30",/g' "$app_dir/package.json"
                package_updated=true
                changes_made=true
            fi
        fi
        
        # Step 6-7: Update middleware.ts if it exists
        if [[ -f "$app_dir/middleware.ts" ]]; then
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
                if grep -q "export async function middleware(" "$app_dir/middleware.ts" && 
                   grep -q "await getMiddleware(request);" "$app_dir/middleware.ts"; then
                    echo "      Middleware already async in $app_name/middleware.ts"
                    middleware_updated=true
                fi
            fi
        else
            echo "      Creating middleware.ts file in $app_name/"
            cat > "$app_dir/middleware.ts" << 'EOF'
import { getMiddleware } from '@truvolv/orson-seelib/middleware';
import type { NextRequest } from 'next/server'

export async function middleware(request: NextRequest) {
  try {
    const response = await getMiddleware(request);
    return response;
  } catch (error) {
    console.error("Error generating middleware:", error);
    //throw error;
  }
}
EOF
            middleware_updated=true
            middleware_created=true
            changes_made=true
        fi
        
        # Determine final status and notes
        if [[ "$package_updated" == true && "$middleware_updated" == true ]]; then
            if [[ "$middleware_created" == true ]]; then
                echo "\"$repo_name\",\"$app_name\",\"success\",\"middleware created and package updated\",\"\"" >> "$LOG_FILE"
            else
                echo "\"$repo_name\",\"$app_name\",\"success\",\"middleware and package updated\",\"\"" >> "$LOG_FILE"
            fi
        elif [[ "$package_updated" == true && "$middleware_updated" == false ]]; then
            if [[ -f "$app_dir/middleware.ts" ]]; then
                echo "\"$repo_name\",\"$app_name\",\"partial\",\"package updated, middleware not updated (strings not found)\",\"\"" >> "$LOG_FILE"
            else
                echo "\"$repo_name\",\"$app_name\",\"partial\",\"package updated, no middleware file found\",\"\"" >> "$LOG_FILE"
            fi
        elif [[ "$package_updated" == false && "$middleware_updated" == true ]]; then
            if [[ "$middleware_created" == true ]]; then
                echo "\"$repo_name\",\"$app_name\",\"partial\",\"middleware created, package not updated (next 14.2.1 not found)\",\"\"" >> "$LOG_FILE"
            else
                echo "\"$repo_name\",\"$app_name\",\"partial\",\"middleware updated, package not updated (next 14.2.1 not found)\",\"\"" >> "$LOG_FILE"
            fi
        elif [[ -f "$app_dir/package.json" || -f "$app_dir/middleware.ts" ]]; then
            notes=""
            if [[ -f "$app_dir/package.json" && ! -f "$app_dir/middleware.ts" ]]; then
                notes="package.json exists but next 14.2.1 not found, no middleware file"
            elif [[ ! -f "$app_dir/package.json" && -f "$app_dir/middleware.ts" ]]; then
                notes="middleware.ts exists but expected strings not found, no package.json"
            else
                notes="files exist but expected strings not found"
            fi
            echo "\"$repo_name\",\"$app_name\",\"no-changes\",\"$notes\",\"\"" >> "$LOG_FILE"
        fi
        
        if [[ "$package_updated" == true && "$middleware_updated" == true ]]; then
            ((apps_fixed++))
            echo "      App fixed! Total fixed: $apps_fixed"
        fi
    done
    
    # Step 8-9: Create branch, commit, push, and create PR if changes were made
    if [[ "$changes_made" == true ]]; then
        # branch_name="chore/TRUSPD-416/update-nextjs-version-and-middleware-async-call"
        
        # echo "  Cleaning up git references..."
        # git fetch --prune origin 2>/dev/null || true
        
        # echo "  Creating branch: $branch_name"
        # if ! git checkout -b "$branch_name" 2>/dev/null; then
        #     echo -e "${YELLOW}  Branch creation failed (likely already exists), discarding local changes${NC}"
        #     echo "\"$repo_name\",\"branch-exists\",\"Branch creation failed, likely already exists - local changes discarded\"" >> "$ERROR_FILE"
            
        #     # Reset any local changes
        #     git reset --hard HEAD
        #     git clean -fd
            
        #     cd - > /dev/null
        #     continue
        # fi
        
        echo "  Committing changes..."
        git add .
        if ! git commit -m "Update Next.js to 14.2.30 and make middleware async

- Updated Next.js version from 14.2.1 to 14.2.30 in package.json files
- Made middleware function async and added await to getMiddleware calls"; then
            echo -e "${RED}  Failed to commit changes${NC}"
            echo "\"$repo_name\",\"commit-failed\",\"Could not commit changes\"" >> "$ERROR_FILE"
            cd - > /dev/null
            continue
        fi
        
        echo "  Pushing branch..."
        # if ! git push origin "$branch_name"; then
        if ! git push; then

            echo -e "${RED}  Failed to push branch${NC}"
            echo "\"$repo_name\",\"push-failed\",\"Could not push branch $branch_name\"" >> "$ERROR_FILE"
            cd - > /dev/null
            continue
        fi
        
        echo "  Creating PR..."
        pr_url=$(gh pr create \
            --title "Update Next.js to 14.2.30 and make middleware async" \
            --body "This PR updates:

- Next.js version from 14.2.1 to 14.2.30 in all apps
- Makes middleware functions async and adds await to getMiddleware calls

This is an automated update across multiple repositories." \
            --head "$branch_name" 2>&1)
        
        # if [[ $? -eq 0 ]]; then
        #     echo -e "${GREEN}  ✓ PR created successfully${NC}"
            
        #     # Use a temporary file to update the CSV
        #     temp_file=$(mktemp)
        #     while IFS= read -r line; do
        #         if [[ "$line" == *"\"$repo_name\","*",\"success\","* ]]; then
        #             # Replace the empty PR link with the actual URL
        #             echo "${line%,\"\"*},\"$pr_url\"" >> "$temp_file"
        #         else
        #             echo "$line" >> "$temp_file"
        #         fi
        #     done < "$LOG_FILE"
        #     mv "$temp_file" "$LOG_FILE"
        # else
        #     echo -e "${RED}  Failed to create PR${NC}"
        #     echo "\"$repo_name\",\"pr-failed\",\"Could not create pull request\"" >> "$ERROR_FILE"
        # fi
    else
        echo -e "${YELLOW}  No changes needed${NC}"
        echo "\"$repo_name\",\"no-changes\",\"Repository processed but no changes were needed\"" >> "$ERROR_FILE"
    fi
    
    cd - > /dev/null
    echo ""
    
done < "$REPO_LIST_FILE"

echo -e "${GREEN}Batch processing completed! Fixed $apps_fixed apps out of target $BATCH_SIZE.${NC}"
echo -e "${GREEN}Check logs.csv for app-level status and error.csv for repo-level issues.${NC}"

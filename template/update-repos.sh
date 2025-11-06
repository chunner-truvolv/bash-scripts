#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(pwd)"
LOG_FILE="$SCRIPT_DIR/logs.csv"
ERROR_FILE="$SCRIPT_DIR/error.csv"
PR_LINKS_FILE="$SCRIPT_DIR/pr-links.txt"
LOG_TRACKING_FILE="$SCRIPT_DIR/logs.txt"
MANUAL_UPDATE_FILE="$SCRIPT_DIR/manual-updates.csv"

BATCH_SIZE=${1:-5}
echo -e "${YELLOW}Batch size set to: $BATCH_SIZE apps${NC}"

echo "Repo,App,Status,Notes,PR Link" > "$LOG_FILE"
echo "Repo,Issue,Details" > "$ERROR_FILE"
echo "Repo,App,Status,Notes" > "$MANUAL_UPDATE_FILE"
echo -e "${GREEN}Created new logs.csv, error.csv, and manual-updates.csv files${NC}"

apps_fixed=0

# Start timestamp for logs tracking file, create if not exists
if [[ ! -f "$LOG_TRACKING_FILE" ]]; then
    echo "Mass repo update started at $(date)" > "$LOG_TRACKING_FILE"
    echo "================================================" >> "$LOG_TRACKING_FILE"
else
    # If file exists, append to it with a new header
    echo "" >> "$LOG_TRACKING_FILE"
    echo "Mass repo update started at $(date)" >> "$LOG_TRACKING_FILE"
    echo "================================================" >> "$LOG_TRACKING_FILE"
fi

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

    if [[ $apps_fixed -ge $BATCH_SIZE ]]; then
        echo -e "${GREEN}Batch limit of $BATCH_SIZE apps reached. Stopping.${NC}"
        break
    fi
    
    echo -e "${YELLOW}Processing: $repo_name (Fixed: $apps_fixed/$BATCH_SIZE)${NC}"
    
    repo_dir="all-repos/$(basename "$repo_name")"
    
    # Step 2: Clone repo if not present
    if [[ ! -d "$repo_dir" ]]; then
        echo "Cloning $repo_name..."
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
    for app_dir in apps/*; do
        [[ ! -d "$app_dir" ]] && continue

        if [[ $apps_fixed -ge $BATCH_SIZE ]]; then
            echo -e "${GREEN}Batch limit of $BATCH_SIZE apps reached. Stopping.${NC}"
            break
        fi
    
        
        app_name=$(basename "$app_dir")
        echo "    Processing app: $app_name"
        echo "    App Directory: $app_dir"

        needs_manual_update=false

        api_route_updated=false
        page_404_updated=false
        page_404_created=false
        core_event_page_updated=false
        core_event_page_created=false
        
        api_route_already_updated=false
        page_404_already_updated=false
        core_event_page_already_updated=false
        
        # Check if API route is already updated
        if [[ -f "$app_dir/app/api/[...slug]/route.ts" ]]; then
            if grep -q "export * from \"@truvolv/orson-seelib/api/router\";" "$app_dir/app/api/[...slug]/route.ts"; then
                api_route_already_updated=true
            fi
        fi
    
        # Check if 404 page is already updated
        if [[ -f "$app_dir/not-found.tsx" ]]; then
            if grep -q "<NotFoundPage slug={params?.slug} />" "$app_dir/not-found.tsx"; then
                page_404_already_updated=true
            fi
        fi

        # Check if Core Events page is already created/updated
        if [[ -f "$app_dir/app/events/[...slug]/page.tsx" ]]; then
            if grep -q "export default async function Event" "$app_dir/app/events/[...slug]/page.tsx"; then
                core_event_page_already_updated=true
            fi
        fi

        if [[ "$api_route_already_updated" == true && "$page_404_already_updated" == true && "$core_event_page_already_updated" == true ]]; then
            echo "\"$repo_name\",\"$app_name\",\"completed\",\"already updated (not counted toward batch)\",\"\"" >> "$LOG_FILE"
            echo "      App already has all three updates, skipping..."
            continue
        fi
        
        # Step 5: Update API route if no custom member edits have been made to the file, the route should exist
        if [[ -f "$app_dir/app/api/[...slug]/route.ts" ]]; then
        if grep -q "import { GET } from \"@truvolv/orson-seelib/api/router\";" "$app_dir/app/api/[...slug]/route.ts" && \
        grep -q "export { GET };" "$app_dir/app/api/[...slug]/route.ts"; then
            echo "      Updating API route in $app_name/app/api/[...slug]/route.ts"
                # Replace all content with new API route content

            cat > "$app_dir/app/api/[...slug]/route.ts" << 'EOF'
// exporting all route handlers from orson-seelib
// we can overwrite specific handlers here per member if needed
export * from "@truvolv/orson-seelib/api/router";
EOF
            api_route_updated=true
            changes_made=true

            else
                echo "      Skipping API route update in $app_name/app/api/[...slug]/route.ts - custom member edits detected"
                echo "\"$repo_name\",\"$app_name\",\"manual-update-required\",\"Custom member edits detected in /app/api/[...slug]/route.ts\"" >> "$MANUAL_UPDATE_FILE"

                needs_manual_update=true
                api_route_updated=false
                changes_made=false
                
            fi
        fi

        # Step 6: Update 404 page if it exists, else create it
        if [[ -f "$app_dir/not-found.tsx" ]]; then
            echo "      Updating 404 page in $app_name/not-found.tsx"
            # Replace all content with new 404 page content

            cat > "$app_dir/not-found.tsx" << 'EOF'
import { Metadata } from "next";
import { generate404PageMeta } from "@truvolv/orson-seelib/lib/generate404PageMeta";
import { NotFoundPage } from "@truvolv/orson-seelib/components/page";

export async function generateMetadata({
  params,
}: {
  params: { slug: string | string[] };
}): Promise<Metadata> {
  try {
    const result = generate404PageMeta({ params });
    return result;
  } catch (error) {
    console.error("Error generating metadata:", error);
    throw error;
  }
}
export default async function Page({
  params,
}: {
  params?: { slug?: string | string[] };
}) {
  return (
    <NotFoundPage slug={params?.slug} />
  );
}
EOF
            
            page_404_updated=true
            changes_made=true
        else
            echo "      Creating 404 page file in $app_name/not-found.tsx"
            cat > "$app_dir/not-found.tsx" << 'EOF'
import { Metadata } from "next";
import { generate404PageMeta } from "@truvolv/orson-seelib/lib/generate404PageMeta";
import { NotFoundPage } from "@truvolv/orson-seelib/components/page";

export async function generateMetadata({
params,
}: {
params: { slug: string | string[] };
}): Promise<Metadata> {
try {
    const result = generate404PageMeta({ params });
    return result;
} catch (error) {
    console.error("Error generating metadata:", error);
    throw error;
}
}
export default async function Page({
params,
}: {
params?: { slug?: string | string[] };
}) {
return (
    <NotFoundPage slug={params?.slug} />
);
}
EOF
            page_404_created=true
            changes_made=true
        fi
        
        # Step 7: Only create Core Events page if it doesn't exist
        if [[ -f "$app_dir/app/events/[...slug]/page.tsx" ]]; then
            echo "      Skipping update, Core Events page in $app_name/app/events/[...slug]/page.tsx already exists"
            
            core_event_page_updated=false
            changes_made=false
        else
            echo "      Creating Core Events page file in $app_name/app/events/[...slug]/page.tsx"
            mkdir -p "$app_dir/app/events/[...slug]"
            cat > "$app_dir/app/events/[...slug]/page.tsx" << 'EOF'
import { CoreEvent } from "@truvolv/orson-seelib/components/event";
import { generateStaticEventParams } from "@truvolv/orson-seelib/lib/generateStaticEventParams";
import { generateEventMeta } from "@truvolv/orson-seelib/lib/generateEventMeta";
import { Metadata } from "next";

export async function generateMetadata({
params,
}: {
params: { slug: string | string[] };
}): Promise<Metadata> {
try {
    const result = generateEventMeta({ params });
    return result;
} catch (error) {
    console.error("Error generating metadata:", error);
    throw error;
}
}

export async function generateStaticParams() {
try {
    const result = generateStaticEventParams();
    return result;
} catch (error) {
    console.error("Error generating static event params:", error);
    throw error;
}
}

export default async function Event({
params,
}: {
params: { slug: string | string[] };
}) {
return (
    <>
    <CoreEvent slug={params.slug} />
    </>
);
}
EOF
            core_event_page_created=true
            changes_made=true
        fi

        # Determine final status and notes based on the updates made
        notes=""
        if [[ "$api_route_updated" == true && "$page_404_updated" == true && "$core_event_page_updated" == true ]]; then
            notes="API route, 404 page, and core events page updated"
            status="success"
        elif [[ "$api_route_updated" == true && "$page_404_created" == true && "$core_event_page_created" == true ]]; then
            notes="API route updated, 404 page and core events page created"
            status="success"
        elif [[ "$api_route_updated" == true && "$page_404_updated" == true && "$core_event_page_created" == true ]]; then
            notes="API route and 404 page updated, core events page created"
            status="success"
        elif [[ "$api_route_updated" == true && "$page_404_created" == true && "$core_event_page_updated" == true ]]; then
            notes="API route updated, 404 page created, core events page updated"
            status="success"
        else
            # Partial updates - build detailed notes
            status="partial"
            if [[ "$api_route_updated" == true ]]; then
                notes="$notes API route updated,"
            else
                notes="$notes API route not updated,"
            fi
            if [[ "$page_404_updated" == true ]]; then
                notes="$notes 404 page updated,"
            elif [[ "$page_404_created" == true ]]; then
                notes="$notes 404 page created,"
            else
                notes="$notes 404 page not updated,"
            fi
            if [[ "$core_event_page_updated" == true ]]; then
                notes="$notes core events page updated,"
            elif [[ "$core_event_page_created" == true ]]; then
                notes="$notes core events page created,"
            else
                notes="$notes core events page not updated,"
            fi
            notes="${notes%,}"  # Remove trailing comma
        fi

        if [[ "$needs_manual_update" == true ]]; then
            echo "\"$repo_name\",\"$app_name\",\"$status, needs manual update\",\"$notes\",\"\"" >> "$LOG_FILE"
        else
            echo "\"$repo_name\",\"$app_name\",\"$status\",\"$notes\",\"\"" >> "$LOG_FILE"
        fi

        # Count toward batch only if all three components were successfully processed
        if [[ "$api_route_updated" == true && ("$page_404_updated" == true || "$page_404_created" == true) && ("$core_event_page_updated" == true || "$core_event_page_created" == true) ]]; then
            ((apps_fixed++))
            echo "APP STATUS: $repo_name/$app_name - $status - $notes" >> "$LOG_TRACKING_FILE"
            echo "    App fixed! Total fixed: $apps_fixed"
        fi
    done
    
    # Start timestamp for PR links file, create if not exists
    if [[ ! -f "$PR_LINKS_FILE" ]]; then
        echo "PR Links from mass repo update started at $(date)" > "$PR_LINKS_FILE"
        echo "================================================" >> "$PR_LINKS_FILE"
    else
        # If file exists, append to it with a new header
        echo "" >> "$PR_LINKS_FILE"
        echo "PR Links from mass repo update started at $(date)" >> "$PR_LINKS_FILE"
        echo "================================================" >> "$PR_LINKS_FILE"
    fi

    # Step 8-9: Create branch, commit, push, and create PR if changes were made
    # if [[ "$changes_made" == true ]]; then
    #     # Comment out lines for Step #8-9 once tested and ready to push to main
    #     branch_name="chore/TRUSPD-587/update-api-route-404-page-core-events-page"
        
    #     echo "  Cleaning up git references..."
    #     git fetch --prune origin 2>/dev/null || true
        
    #     echo "  Creating branch: $branch_name"
    #     if ! git checkout -b "$branch_name" 2>/dev/null; then
    #         echo -e "${YELLOW}  Branch creation failed (likely already exists), discarding local changes${NC}"
    #         echo "\"$repo_name\",\"branch-exists\",\"Branch creation failed, likely already exists - local changes discarded\"" >> "$ERROR_FILE"
            
    #         # Reset any local changes
    #         git reset --hard HEAD
    #         git clean -fd
            
    #         cd - > /dev/null
    #         continue
    #     fi
        
    #     echo "  Committing changes..."
    #     git add .
    #     if ! git commit -m "Update API route to include all handlers from orson-seelib, update or create 404 page skeleton, and update or create core events page"; then
    #         echo -e "${RED}  Failed to commit changes${NC}"
    #         echo "\"$repo_name\",\"commit-failed\",\"Could not commit changes\"" >> "$ERROR_FILE"
    #         cd - > /dev/null
    #         continue
    #     fi
        
    #     echo "  Pushing branch..."
    #     # Comment out line 451 and uncomment next line once tested to push without PR creation
    #     if ! git push origin "$branch_name"; then
    #     # if ! git push; then

    #         echo -e "${RED}  Failed to push branch${NC}"
    #         echo "\"$repo_name\",\"push-failed\",\"Could not push branch $branch_name\"" >> "$ERROR_FILE"
    #         cd - > /dev/null
    #         continue
    #     fi
        
    #     echo "  Creating PR..."
    #     pr_url=$(gh pr create \
    #         --title "Update API route, 404 page, and core events page" \
    #         --body "This PR updates:

    #         - API route to include all handlers from orson-seelib
    #         - 404 page skeleton to use NotFoundPage component from orson-seelib
    #         - Events page to display separate events page using CoreEvent component from orson-seelib

    #         Ticket: https://truvolv-company.monday.com/item/TRUSPD-583

    #         This is an automated update across multiple repositories." \
    #         --head "$branch_name" 2>&1)

    #     if [[ $? -eq 0 ]]; then
    #         echo -e "${GREEN}  ✓ PR created successfully${NC}"
            
    #         # Add to PR links file
    #         echo "$repo_name: $pr_url" >> "$PR_LINKS_FILE"
            
    #         # Update the CSV with PR URL for successful app updates
    #         temp_file=$(mktemp)
    #         while IFS= read -r line; do
    #             if [[ "$line" == *"\"$repo_name\","*"\",\"success\","* ]]; then
    #                 # Replace the empty PR link with the actual URL
    #                 echo "${line%,\"\"*},\"$pr_url\"" >> "$temp_file"
    #             else
    #                 echo "$line" >> "$temp_file"
    #             fi
    #         done < "$LOG_FILE"
    #         mv "$temp_file" "$LOG_FILE"
    #     else
    #         echo -e "${RED}  Failed to create PR${NC}"
    #         echo "\"$repo_name\",\"pr-failed\",\"Could not create pull request\"" >> "$ERROR_FILE"
    #     fi
    # else
    #     echo -e "${YELLOW}  No changes needed${NC}"
    #     echo "\"$repo_name\",\"no-changes\",\"Repository processed but no changes were needed\"" >> "$ERROR_FILE"
    # fi
    
    # cd - > /dev/null
    # echo ""
    
done < "$REPO_LIST_FILE"

# End timestamp for PR links file
echo "================================================" >> "$PR_LINKS_FILE"
echo "Mass repo update completed at $(date)" >> "$PR_LINKS_FILE"

# End timestamp for logs tracking file
echo "================================================" >> "$LOG_TRACKING_FILE"
echo "Mass repo update completed at $(date)" >> "$LOG_TRACKING_FILE"

echo -e "${GREEN}Batch processing completed! Fixed $apps_fixed apps out of target $BATCH_SIZE.${NC}"
echo -e "${GREEN}Check logs.csv for app-level status and error.csv for repo-level issues.${NC}"
echo -e "${GREEN}PR links saved to: $PR_LINKS_FILE${NC}"
echo -e "${GREEN}Detailed logs saved to: $LOG_TRACKING_FILE${NC}"
## 🧩 Repository Batch Updater Script

This script was written for batch updates across our member repos. In this instance, the intent was to update the API routes from Orson-Seelib, use a 404 page component from Orson-Seelib, and add an Events page route for the Events collection.\

### 🚀 What It Does

1. **Reads a list of repositories**

   - The script expects a `repo-list.txt` file containing one GitHub repository per line (`org-name/repo-name` format).
   - Skips blank lines and comments (`#`).

2. **Processes repositories in batches**

   - A batch size can be passed as an argument (default: `5` apps).
   - Stops automatically when the batch limit is reached.

3. **Clones and prepares each repo**

   - Clones each repository into `all-repos/` if it’s not already there.
   - Checks out the `main` or `master` branch and pulls the latest changes.

4. **Validates TurboRepo structure**

   - Skips repositories that don’t contain a `turbo.json` file or an `apps/` directory. (ie will skip repos like TruSpeed if they end up in the list by accident)

5. **Iterates through all apps inside `apps/`**  
   For each app subdirectory, the script:

   - **Updates API route**
     - Checks to see if `export * from \"@truvolv/orson-seelib/api/router\";` in `api/[...slug]/route.ts` exists within the file and if not, and replaces all content with
     ```
      // exporting all route handlers from orson-seelib
      // we can overwrite specific handlers here per member if needed
      export * from "@truvolv/orson-seelib/api/router";
     ```
   - **Creates / Updates `not-found.tsx`**

     - Checks to see if `not-found.tsx` page exists, if not, creates one
     - If it exists, it overwrites all file content with the new 404 page skeleton we are adding otherwise creates a new file with the code below.

     ```
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
     ```

   - **Creates / Updates Events page**

     - Checks to see if `events/[...slug]/page.tsx` page exists, if not, creates one
     - If it exists, it overwrites all file content with the new Events page content we are adding otherwise creates a new file with the code below.

     ```
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
     ```

6. **Tracks progress and logs results**

   - Logs per-app updates in `logs.csv` with details on status (`success`, `partial`, `no-changes`, etc.)
   - Logs repo-level issues in `error.csv` (e.g., clone failures, missing directories).

7. **Commits and pushes changes**

   - Commits updates with a descriptive message.
   - (Optional) Creates a pull request via GitHub CLI — this section is partially commented out for manual control.

8. **Provides color-coded terminal output**
   - Green for success, yellow for skips or partial updates, red for errors.

### 📁 Output Files

- **`logs.csv`** — App-level results including repo name, app name, status, and notes.
- **`error.csv`** — Repository-level issues or skips (e.g., missing branches, failed clones).
- **`all-repos/`** — Local clones of all processed repositories.

### 🧠 Example Workflow

```bash
# Run script with default batch size of 5
bash update-repos.sh

# Run script to process 10 apps
bash update-repos.sh 10
```

### ⚙️ Requirements

- GitHub CLI (`gh`) authenticated with repo access
- Bash shell (macOS or Linux environment)
- Git installed
- Access to all repos listed in `repo-list.txt`

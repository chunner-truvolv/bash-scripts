## 🧩 Repository Batch Updater Script
This script was written for batch updates across our member repos. In this instance, the intent was to update the NextJS version and to make the middleware asynchronous.

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
   - **Updates Next.js version**  
     - Looks for `"next": "14.2.1",` in `package.json` and replaces it with `"next": "14.2.30",`.
   - **Ensures middleware is async**  
     - Converts `export function middleware(...)` → `export async function middleware(...)`.
     - Adds `await` before `getMiddleware(request)` calls.
   - **Creates a default `middleware.ts`** if none exists, with a standard async template.

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
bash update-repose.sh 10
```

### ⚙️ Requirements

- GitHub CLI (`gh`) authenticated with repo access  
- Bash shell (macOS or Linux environment)  
- Git installed  
- Access to all repos listed in `repo-list.txt`

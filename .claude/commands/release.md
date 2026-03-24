Build, sign, notarize, and publish a Prowl release.

1. Verify current branch is `main`: `git branch --show-current`
   - If not on main, abort and tell the user to switch first
2. Verify working tree is clean: `git status --porcelain`
   - If dirty, list the changes and ask whether to proceed or abort
3. Determine the version:
   - If `$ARGUMENTS` is provided, use it as the version (e.g., `2026.3.18`)
   - Otherwise, default to today's date format and confirm with the user before proceeding
4. Run the release script: `./doc-onevcat/scripts/release.sh <VERSION>`
   - The script will pause after generating release notes and prompt for confirmation
   - If running non-interactively (e.g., through Claude), the script skips the interactive prompt.
     In that case, **you must** read `build/release-notes.md` after the script generates it,
     show the release notes to the user, and get explicit confirmation before the build proceeds.
     To do this, run the script in two phases:
     1. Generate notes only: run up to note generation, then read and display `build/release-notes.md`
     2. After user confirms, run the full release script (it will reuse the confirmed notes via `--notes-file build/release-notes.md`)
5. Report the GitHub release URL and remind the user to verify:
   - The DMG downloads and installs correctly
   - Sparkle update check works (launch app → Check for Updates)
   - The appcast at `https://prowl.onev.cat/appcast.xml` is updated

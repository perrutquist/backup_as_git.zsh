backup_as_git_setup.zsh — Back up any folder using a separate Git repo

This repository provides a setup script that creates an external Git repository for a given folder and installs a cron job to commit changes automatically every hour. It is designed for directories that do not already contain a `.git` directory or a `.gitignore`.

Quick start

- Command:
  Running `backup_as_git_setup.zsh NAME WORKDIR GITDIR [IGNORE]` will:
  - Initialize a Git repository at `GITDIR` (outside of `WORKDIR`), and write ignore patterns from `IGNORE` (semicolon-separated) to `GITDIR/.git/info/exclude`.
  - Create a wrapper script `~/backup_${NAME}_as_git.zsh`.
  - Add an hourly cron job that runs the wrapper.
  - Print a summary including how to view or modify your crontab.

- Safety:
  If `GITDIR` is inside `WORKDIR`, setup aborts with an error.

What gets created

- External repository at `GITDIR`:
  - Uses `--git-dir="$GITDIR/.git"` and `--work-tree="$WORKDIR"` when committing.
  - Ignore patterns are written to `GITDIR/.git/info/exclude` so you don’t have to modify the work directory.

- Wrapper script at `~/backup_${NAME}_as_git.zsh`:
  - Commits changes with the message `autocommit` only if there are modifications.
  - No remote is configured or pushed to by default.

- Cron entry:
  - Runs at minute 0 of every hour.
  - If a cron entry for the wrapper already exists, another is not added.

Arguments

- NAME: Identifier used in generated script filenames (letters, digits, `_`, `-`).
- WORKDIR: Directory to back up; must exist and must NOT contain `GITDIR`.
- GITDIR: External repository directory; created if missing.
- IGNORE (optional): Semicolon-separated ignore patterns written to `.git/info/exclude`, e.g. `.DS_Store;*.tmp;node_modules/`.

Examples

- Basic (no ignore patterns):
  backup_as_git_setup.zsh notes ~/Documents/Notes ~/.backups/notes

- With ignore patterns:
  backup_as_git_setup.zsh proj ~/Projects/MyApp ~/.backups/myapp ".DS_Store;*.log;node_modules/;dist/"

Inspect and manage cron

- View current crontab:
  crontab -l

- Edit crontab:
  crontab -e

- Remove the created cron entry later:
  crontab -l | grep -v "$HOME/backup_${NAME}_as_git.zsh" | crontab -

Uninstall / cleanup

- Delete the wrapper:
  rm -f "$HOME/backup_${NAME}_as_git.zsh"

- Optionally remove the external repo (this deletes your backup data):
  rm -rf "GITDIR"

Notes and tips

- Paths with spaces: Quote your arguments.
- Ignore patterns: Separate with semicolons; entries are appended to `.git/info/exclude` if not already present.
- No push by default: If you want off-machine backup, add a remote to `GITDIR` and push from there on your own schedule.
- Cron environment: Cron runs with a minimal environment; the wrapper uses absolute paths and does not require a login shell.

License

MIT License. See the LICENSE file for details.

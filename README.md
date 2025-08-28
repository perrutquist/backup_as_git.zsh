# backup_as_git_setup.zsh - Back up a folder to an external Git repo

`backup_as_git_setup.zsh` is a setup script that creates an external Git repository for a given folder and installs a cron job to commit changes automatically every hour. 

This script was mainly written by AI, but it works for me. I use this to backup some of my iCloud directories onto a Mac Mini, to give me access to the history of those directories.

## Quick start

Running `backup_as_git_setup.zsh NAME WORKDIR GITDIR [IGNORE]` will:
- Initialize a Git repository at `GITDIR` (outside of `WORKDIR`), and write ignore patterns from `IGNORE` (semicolon-separated) to `GITDIR/.git/info/exclude`.
- Create a wrapper script `~/backup_${NAME}_as_git.zsh`.
- Add an hourly cron job that runs the wrapper.
- Print a summary including how to view or modify your crontab.

If `GITDIR` is inside `WORKDIR`, setup aborts with an error.

## Arguments

- NAME: Identifier used in generated script filenames (letters, digits, `_`, `-`).
- WORKDIR: Directory to back up; must exist and must NOT contain `GITDIR`.
- GITDIR: External repository directory; created if missing.
- IGNORE (optional): Semicolon-separated ignore patterns, e.g. `.DS_Store;*.tmp;node_modules/`.

## Example

  backup_as_git_setup.zsh proj ~/Projects/MyApp ~/.backups/myapp ".DS_Store;*.log;node_modules/;dist/"

## Note

There's no push by default: If you want off-machine backup, add a remote to `GITDIR` and modify the wrapper script to do a push.

## License

MIT License. See the LICENSE file for details.

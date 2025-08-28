Running `backup_as_git_setup.zsh NAME WORKDIR GITDIR [IGNORE]` 
- Initializes a git repository at `GITDIR` (outside of `WORKDIR`), with an exclude file that lists anything listed in `IGNORE` (semicolon-separated),
- Creates `backup_$NAME_as_git.zsh` in the users home directory, and
- Adds that script to the user's crontab, to run every hour.
- Prints a friendly message informing the user of what has been done, and how to modfiy the crontab.

If `GITDIR` is inside of `WORKDIR`, the setup will abort with an error message.

The auto-generated script `backup_$NAME_as_git.zsh` does a backup of a directory (that is not assumed to contain a `.git` directory or a `.gitignore` file) by commiting all changes (if any) to the external repo at `GITDIR` with a message that says "autocommit".

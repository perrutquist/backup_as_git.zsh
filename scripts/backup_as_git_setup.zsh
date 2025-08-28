#!/bin/zsh
# backup_as_git_setup.zsh NAME WORKDIR GITDIR [IGNORE]
# - Initializes a git repository at GITDIR (outside of WORKDIR), with an exclude file listing patterns from IGNORE (semicolon-separated).
# - Creates $HOME/backup_${NAME}_as_git.zsh.
# - Adds the wrapper script to the user's crontab to run every hour.
# - Prints a friendly message informing the user of what was done and how to modify the crontab.
#
# If GITDIR is inside WORKDIR, the setup aborts with an error.

set -u

print_usage() {
  cat <<'USAGE'
Usage:
  backup_as_git_setup.zsh NAME WORKDIR GITDIR [IGNORE]

Arguments:
  NAME    - A short name (letters, digits, underscores or hyphens) used in generated script filenames.
  WORKDIR - Path to the directory to back up. Must exist and must NOT contain GITDIR.
  GITDIR  - Path to the external git repository directory. Will be created if it does not exist.
  IGNORE  - Optional; semicolon-separated patterns to ignore (written to .git/info/exclude).

Example:
  backup_as_git_setup.zsh docs /Users/alex/Documents /Users/alex/.backups/docs ".DS_Store;*.tmp;node_modules/"

USAGE
}

die() {
  print -ru2 -- "Error: $*"
  exit 1
}

info() {
  print -- "$*"
}

# Ensure git is available
command -v git >/dev/null 2>&1 || die "git is required but not found in PATH."

# Validate args
if (( $# < 3 || $# > 4 )); then
  print_usage
  exit 2
fi

NAME="$1"
WORKDIR_RAW="$2"
GITDIR_RAW="$3"
IGNORE="${4:-}"

# Validate NAME (restrict to safe filename characters)
if [[ ! "$NAME" =~ ^[[:alnum:]_-]+$ ]]; then
  die "NAME must contain only letters, digits, underscores, or hyphens."
fi

# Resolve absolute, normalized paths (zsh :A modifier)
WORKDIR="${WORKDIR_RAW:A}"
GITDIR="${GITDIR_RAW:A}"

# Strip trailing slashes for reliable comparisons
WORKDIR="${WORKDIR%/}"
GITDIR="${GITDIR%/}"

# Validate WORKDIR exists and is a directory
[[ -d "$WORKDIR" ]] || die "WORKDIR does not exist or is not a directory: $WORKDIR"

# Abort if GITDIR is inside WORKDIR
if [[ "$GITDIR" == "$WORKDIR" || "$GITDIR" == "$WORKDIR"/* ]]; then
  die "GITDIR ($GITDIR) must not be inside WORKDIR ($WORKDIR)."
fi

# Prepare GITDIR and initialize repository if needed
mkdir -p "$GITDIR" || die "Failed to create GITDIR: $GITDIR"

if [[ ! -d "$GITDIR/.git" ]]; then
  info "Initializing git repository at: $GITDIR"
  git init "$GITDIR" >/dev/null 2>&1 || die "git init failed at $GITDIR"
else
  info "Using existing git repository at: $GITDIR"
fi

# Write ignore patterns to .git/info/exclude (idempotent)
exclude_file="$GITDIR/.git/info/exclude"
mkdir -p "$GITDIR/.git/info" || die "Failed to create repo info dir."
touch "$exclude_file" || die "Failed to create exclude file."

# Add header once
header="# Added by backup_as_git_setup.zsh for NAME=$NAME (WORKDIR=$WORKDIR)"
if ! grep -Fqx "$header" "$exclude_file" 2>/dev/null; then
  {
    print -- ""
    print -- "$header"
  } >>"$exclude_file" || die "Failed to update exclude file."
fi

if [[ -n "$IGNORE" ]]; then
  # Split IGNORE on semicolons and append patterns if not already present
  for pat in "${(@s:;:)IGNORE}"; do
    # Trim surrounding whitespace
    pat="${pat#"${pat%%[![:space:]]*}"}"
    pat="${pat%"${pat##*[![:space:]]}"}"
    [[ -z "$pat" ]] && continue
    if ! grep -Fqx -- "$pat" "$exclude_file" 2>/dev/null; then
      print -- "$pat" >>"$exclude_file" || die "Failed to append pattern to exclude: $pat"
    fi
  done
fi


# Prepare placeholder values
# Use printf %q to properly escape paths for zsh strings
escaped_name="$NAME"
escaped_workdir="$WORKDIR"
escaped_gitdir="$GITDIR"

# Create wrapper script that cron will call
backup_dir="$HOME/.backup_as_git"
mkdir -p "$backup_dir" || die "Failed to create backup scripts directory: $backup_dir"
wrapper_script="$backup_dir/backup_${NAME}_as_git.zsh"
cat >"$wrapper_script" <<'WRAPPERSCRIPT'
#!/bin/zsh
set -u

NAME="@NAME@"
WORKDIR="@WORKDIR@"
GITDIR="@GITDIR@"
ERROR_LOG="$HOME/backup_${NAME}_as_git_error.log"

git_cmd=(git --git-dir="$GITDIR/.git" --work-tree="$WORKDIR")

log_error() {
  print -r -- "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >>"$ERROR_LOG"
}

# Verify repository exists
if [[ ! -d "$GITDIR/.git" ]]; then
  log_error "Error: repository not found at $GITDIR/.git"
  exit 1
fi

# Ensure worktree directory exists
if [[ ! -d "$WORKDIR" ]]; then
  log_error "Error: WORKDIR missing: $WORKDIR"
  exit 1
fi

# Refresh index and commit any changes
changes="$("${git_cmd[@]}" status --porcelain 2>/dev/null)"
if [[ -n "$changes" ]]; then
  if ! "${git_cmd[@]}" add -A; then
    log_error "Error: git add failed."
    exit 1
  fi
  if ! "${git_cmd[@]}" commit -m "autocommit" >/dev/null 2>&1; then
    log_error "Error: git commit failed."
    exit 1
  fi
else
  :
fi
WRAPPERSCRIPT

# Substitute placeholders in wrapper script
tmp_wrap="$wrapper_script.tmp.$$"
sed \
  -e "s|@NAME@|$escaped_name|g" \
  -e "s|@WORKDIR@|$escaped_workdir|g" \
  -e "s|@GITDIR@|$escaped_gitdir|g" \
  "$wrapper_script" > "$tmp_wrap" && mv "$tmp_wrap" "$wrapper_script" || die "Failed to finalize wrapper script."
chmod 700 "$wrapper_script" || die "Failed to chmod wrapper script."

# Add to crontab hourly if not already present
cron_line="0 * * * * $wrapper_script >/dev/null 2>&1"
if crontab -l 2>/dev/null | grep -Fq -- "$wrapper_script"; then
  info "Cron entry already present for: $wrapper_script"
else
  # Preserve existing crontab; append our line
  (crontab -l 2>/dev/null; print -- "$cron_line") | crontab - || die "Failed to install crontab entry."
  info "Added hourly cron job."
fi

# Friendly summary
cat <<SUMMARY

Setup complete.

- Repository:
    $GITDIR
  (Initialized: $( [[ -d "$GITDIR/.git" ]] && print yes || print no ))

- Work directory (backed up):
    $WORKDIR

- Exclude patterns file:
    $exclude_file

- Scripts:
    Wrapper: $wrapper_script

- Cron:
    $cron_line

To view or edit your crontab:
  crontab -l
  crontab -e

To remove the cron entry later, run:
  crontab -l | grep -v "$wrapper_script" | crontab -

SUMMARY

exit 0

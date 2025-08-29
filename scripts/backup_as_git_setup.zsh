#!/bin/zsh
# backup_as_git_setup.zsh NAME WORKDIR GITDIR [IGNORE]
# - Initializes a git repository at GITDIR (outside of WORKDIR), with an exclude file listing patterns from IGNORE (semicolon-separated).
# - Creates $HOME/backup_${NAME}_as_git.zsh.
# - On macOS, installs a launchd LaunchAgent to run the backup hourly (falls back to cron on other systems).
# - Prints a friendly message informing the user of what was done and how to manage the LaunchAgent or cron entry.
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

# Ensure git is available and capture absolute path
GIT_BIN="$(command -v git 2>/dev/null)"
[[ -n "$GIT_BIN" ]] || die "git is required but not found in PATH."

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
escaped_gitbin="$GIT_BIN"

# Create wrapper script that cron will call
backup_dir="$HOME/.backup_as_git"
mkdir -p "$backup_dir" || die "Failed to create backup scripts directory: $backup_dir"
wrapper_script="$backup_dir/backup_${NAME}_as_git.zsh"
cat >"$wrapper_script" <<'WRAPPERSCRIPT'
#!/bin/zsh
set -u

# Minimal PATH for cron
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

NAME="@NAME@"
WORKDIR="@WORKDIR@"
GITDIR="@GITDIR@"
ERROR_LOG="$HOME/backup_${NAME}_as_git_error.log"
GIT_BIN="@GIT_BIN@"

git_cmd=("$GIT_BIN" -c core.hooksPath=/dev/null --git-dir="$GITDIR/.git" --work-tree="$WORKDIR")

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

# Acquire lock to prevent overlapping runs (treat >24h locks as stale)
lockdir="$GITDIR/.git/.backup_as_git.lock"

# If a lock exists and is older than 24 hours, consider it stale and remove it
if [[ -d "$lockdir" ]]; then
  now_epoch="$(date +%s)"
  # Try macOS/BSD stat first, then GNU coreutils
  if mtime_epoch="$(stat -f %m "$lockdir" 2>/dev/null)"; then
    :
  elif mtime_epoch="$(stat -c %Y "$lockdir" 2>/dev/null)"; then
    :
  else
    mtime_epoch=""
  fi
  if [[ -n "$mtime_epoch" ]]; then
    age_sec=$(( now_epoch - mtime_epoch ))
    if (( age_sec > 86400 )); then
      rmdir "$lockdir" 2>/dev/null || rm -rf "$lockdir" 2>/dev/null
    fi
  fi
fi

if ! mkdir "$lockdir" 2>/dev/null; then
  # Another instance is running; exit quietly
  exit 0
fi
trap 'rmdir "$lockdir" 2>/dev/null' EXIT HUP INT TERM

# Refresh index and commit any changes
changes="$("${git_cmd[@]}" status --porcelain 2>&1)"
status_rc=$?
if (( status_rc != 0 )); then
  log_error "Error: git status failed (exit $status_rc): $changes"
  exit 1
fi
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
  -e "s|@GIT_BIN@|$escaped_gitbin|g" \
  "$wrapper_script" > "$tmp_wrap" && mv "$tmp_wrap" "$wrapper_script" || die "Failed to finalize wrapper script."
chmod 700 "$wrapper_script" || die "Failed to chmod wrapper script."

# Install scheduler: launchd on macOS (fallback to cron)
SCHEDULER_SUMMARY=""
LAUNCHCTL_BIN="$(command -v launchctl 2>/dev/null)"
if [[ "$(uname -s)" == "Darwin" && -n "$LAUNCHCTL_BIN" ]]; then
  launch_agents_dir="$HOME/Library/LaunchAgents"
  mkdir -p "$launch_agents_dir" || die "Failed to create LaunchAgents directory: $launch_agents_dir"
  label="com.backup_as_git.${NAME}"
  plist="$launch_agents_dir/$label.plist"
  stdout_log="$HOME/Library/Logs/backup_${NAME}_as_git.out.log"
  stderr_log="$HOME/Library/Logs/backup_${NAME}_as_git.err.log"
  cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>$wrapper_script</string>
  </array>
  <key>StartInterval</key>
  <integer>3600</integer>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$stdout_log</string>
  <key>StandardErrorPath</key>
  <string>$stderr_log</string>
</dict>
</plist>
EOF
  "$LAUNCHCTL_BIN" unload -w "$plist" >/dev/null 2>&1 || true
  "$LAUNCHCTL_BIN" load -w "$plist" || die "Failed to load LaunchAgent: $plist"
  info "Installed hourly launchd agent: $label"
  SCHEDULER_SUMMARY=$'- LaunchAgent:\n    '"$plist"$'\n    Label: '"$label"$'\n    StartInterval: 3600\n\nTo manage:\n  launchctl list | grep -F '"$label"$'\n  launchctl unload -w '"$plist"$'\n  launchctl load -w '"$plist"$'\n\nLogs:\n  '"$stdout_log"$'\n  '"$stderr_log"
else
  # Add to crontab hourly if not already present
  cron_line="0 * * * * $wrapper_script >/dev/null 2>&1"
  if crontab -l 2>/dev/null | grep -Fq -- "$wrapper_script"; then
    info "Cron entry already present for: $wrapper_script"
  else
    # Preserve existing crontab; append our line
    (crontab -l 2>/dev/null; print -- "$cron_line") | crontab - || die "Failed to install crontab entry."
    info "Added hourly cron job."
  fi
  SCHEDULER_SUMMARY=$'- Cron:\n    '"$cron_line"$'\n\nTo view or edit your crontab:\n  crontab -l\n  crontab -e\n\nTo remove the cron entry later, run:\n  crontab -l | grep -v "'"$wrapper_script"'" | crontab -'
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

$SCHEDULER_SUMMARY

SUMMARY

exit 0

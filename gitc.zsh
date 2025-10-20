# ============================================================================
# gitc - Git clone with tmux sessions and smart organization
# ============================================================================
# A smart git clone wrapper that:
# - Clones repos into organized directory structure (host/owner/repo)
# - Creates a tmux session and automatically cd's into the cloned directory
# - Supports GitHub shortcuts (just repo name or owner/repo)
# - Works with any git hosting service (GitHub, GitLab, Bitbucket, etc.)
#
# Can be used standalone or as a dependency for other tools like devt
# ============================================================================

# ============================================================================
# Configuration
# ============================================================================

# Base directory where gitc will clone repositories
# Repos will be organized as: GITC_CLONE_DIR/host/owner/repo
GITC_CLONE_DIR="${HOME}/src"

# Default git host for shortcuts (when just providing repo name or owner/repo)
GITC_DEFAULT_HOST="github.com"

# ============================================================================
# Shared utility functions (exported for use by other tools)
# ============================================================================

# Generic function to create a tmux session and run a command
# Falls back to running command directly if tmux is not available
_tmux_session_with_command() {
  local base_command="$1"
  local action="$2"
  shift 2
  local args="$@"
  
  # Check if tmux is available
  if ! command -v tmux &> /dev/null; then
    # Run command directly without tmux
    eval "$base_command $action $args"
    return $?
  fi
  
  # Determine session name
  if [[ "$action" == "clone" ]]; then
    local repo_name="${1##*/}"
    repo_name="${repo_name%.git}"
    local session_name="$repo_name"
  else
    # For cd, extract directory name
    local session_name="${1##*/}"
  fi
  
  # Create and attach to tmux session, running command inside
  tmux new-session -s "$session_name" -d
  tmux send-keys -t "$session_name" "$base_command $action $args" C-m
  tmux attach-session -t "$session_name"
}

# Fetch and cache GitHub repos for a given user/org
_fetch_github_repos() {
  local owner="$1"
  local cache_file="$2"
  local cache_time="${3:-3600}"  # Default 1 hour cache
  local max_repos="${4:-1000}"
  
  mkdir -p "${HOME}/.cache"
  
  local -a repos
  
  # Check cache
  if [[ -f "$cache_file" ]] && [[ $(($(date +%s) - $(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null))) -lt $cache_time ]]; then
    repos=("${(@f)$(cat $cache_file)}")
  else
    # Fetch repos from GitHub
    repos=("${(@f)$(gh repo list "$owner" --limit "$max_repos" --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null)}")
    if [[ ${#repos[@]} -gt 0 ]]; then
      printf '%s\n' "${repos[@]}" > "$cache_file"
    fi
  fi
  
  # Return repos via stdout
  printf '%s\n' "${repos[@]}"
}

# Get current GitHub user
_get_github_user() {
  gh api user --jq .login 2>/dev/null
}

# Generic function to refresh GitHub repo cache
_refresh_github_cache() {
  local owner="$1"
  local cache_file="$2"
  local limit="${3:-1000}"
  local display_name="${4:-$owner}"
  
  if [[ -z "$owner" || -z "$cache_file" ]]; then
    echo "Error: Owner and cache file must be specified"
    return 1
  fi
  
  echo "Refreshing ${display_name}'s repos cache..."
  gh repo list "$owner" --limit "$limit" --json nameWithOwner --jq '.[].nameWithOwner' > "$cache_file"
  if [[ $? -eq 0 ]]; then
    echo "Cache refreshed!"
  else
    echo "Error: Failed to refresh cache"
    return 1
  fi
}

# ============================================================================
# gitc command - tmux sessions with git clone
# ============================================================================

gitc() {
  # Validate arguments
  if [[ $# -lt 1 ]]; then
    echo "Usage: gitc <repo>"
    return 1
  fi
  
  # Ensure base clone directory exists
  if [[ ! -d "$GITC_CLONE_DIR" ]]; then
    mkdir -p "$GITC_CLONE_DIR"
  fi
  
  local repo="$1"
  local git_url="$repo"
  local target_path=""
  
  # Parse the input to extract host/owner/repo and construct proper git URL
  if [[ "$repo" =~ ^https?://([^/]+)/(.+)$ ]]; then
    # HTTPS URL: https://host.com/owner/repo or https://host.com/owner/repo.git
    local host="${match[1]}"
    local path="${match[2]%.git}"
    target_path="${host}/${path}"
    git_url="$repo"
  elif [[ "$repo" =~ ^git@([^:]+):(.+)$ ]]; then
    # SSH URL: git@host.com:owner/repo or git@host.com:owner/repo.git
    local host="${match[1]}"
    local path="${match[2]%.git}"
    target_path="${host}/${path}"
    git_url="$repo"
  elif [[ "$repo" == */* && "$repo" != *:* && "$repo" != http* ]]; then
    # owner/repo format - assume default host (GitHub)
    target_path="${GITC_DEFAULT_HOST}/${repo}"
    git_url="git@${GITC_DEFAULT_HOST}:${repo}.git"
  else
    # Just repo name - prepend current user and assume default host
    local github_user=$(_get_github_user)
    if [[ -n "$github_user" ]]; then
      target_path="${GITC_DEFAULT_HOST}/${github_user}/${repo}"
      git_url="git@${GITC_DEFAULT_HOST}:${github_user}/${repo}.git"
    else
      echo "Error: Could not determine GitHub user. Run: gh auth login"
      return 1
    fi
  fi

  # Create target directory structure: GITC_CLONE_DIR/host/owner/repo
  local target_dir="${GITC_CLONE_DIR}/${target_path}"
  mkdir -p "$(dirname "$target_dir")"
  
  shift
  
  # Get repo name for session
  local repo_name="${target_path##*/}"
  
  # Check if tmux is available
  if command -v tmux &> /dev/null; then
    # Create and attach to tmux session, running git clone with target directory
    tmux new-session -s "$repo_name" -d
    tmux send-keys -t "$repo_name" "git clone $git_url $target_dir $@ && cd $target_dir" C-m
    tmux attach-session -t "$repo_name"
  else
    # Run git clone directly without tmux
    git clone "$git_url" "$target_dir" "$@" && cd "$target_dir"
  fi
}

gitc-refresh-cache() {
  local github_user=$(_get_github_user)
  if [[ -z "$github_user" ]]; then
    echo "Error: Could not get GitHub user. Run: gh auth login"
    return 1
  fi
  
  _refresh_github_cache "$github_user" "${HOME}/.cache/gitc-${github_user}-repos" 1000 "$github_user"
}

_gitc() {
  local current_word="${words[CURRENT]}"
  local -a repos
  
  # Check if user is typing "username/" pattern
  if [[ "$current_word" == */* ]]; then
    local typed_user="${current_word%%/*}"
    local cache_file="${HOME}/.cache/gitc-${typed_user}-repos"
    
    # Fetch repos for the specified user
    local -a user_repos
    user_repos=("${(@f)$(_fetch_github_repos "$typed_user" "$cache_file" 3600 1000)}")
    
    if [[ ${#user_repos[@]} -gt 0 && ${#user_repos[@]} -le 500 ]]; then
      # Only show completions if user doesn't have too many repos
      _describe "GitHub repositories for $typed_user" user_repos
    else
      _message "Type full repo name: $typed_user/repo-name"
    fi
  else
    # Default to current user's repos
    local github_user=$(_get_github_user)
    if [[ -n "$github_user" ]]; then
      local cache_file="${HOME}/.cache/gitc-${github_user}-repos"
      repos=("${(@f)$(_fetch_github_repos "$github_user" "$cache_file")}")
      
      # Strip username prefix for cleaner completion
      local -a repo_names
      for repo in "${repos[@]}"; do
        repo_names+=("${repo#*/}:$repo")
      done
      
      if [[ ${#repo_names[@]} -gt 0 ]]; then
        _describe "Your GitHub repositories" repo_names
      else
        _message "No repositories found"
      fi
    else
      _message "Install gh CLI and run: gh auth login"
    fi
  fi
}

compdef _gitc gitc


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

# Autocomplete configuration
# Maximum number of repos to load for full autocomplete
# If a user/org has more repos, switch to incremental search
GITC_AUTOCOMPLETE_MAX_REPOS="${GITC_AUTOCOMPLETE_MAX_REPOS:-500}"

# Minimum characters to type before triggering incremental search
GITC_AUTOCOMPLETE_MIN_SEARCH_CHARS="${GITC_AUTOCOMPLETE_MIN_SEARCH_CHARS:-2}"

# Cache time for repo listings (in seconds)
GITC_CACHE_TIME="${GITC_CACHE_TIME:-3600}"  # 1 hour default

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

# Search GitHub repos by query string (for large orgs with many repos)
# This is much faster than fetching all repos when there are 10k+ repos
_search_github_repos() {
  local org="$1"
  local query="$2"
  local limit="${3:-50}"
  
  if [[ -z "$org" ]]; then
    return 1
  fi
  
  # If query is too short, don't search to avoid too many results
  if [[ ${#query} -lt 2 ]]; then
    return 1
  fi
  
  # Search for repos in the org matching the query
  # Note: gh search repos uses 'fullName' not 'nameWithOwner'
  gh search repos "$query" --owner "$org" --limit "$limit" --json fullName --jq '.[].fullName' 2>/dev/null
}

# Shared autocomplete function for GitHub repos with smart search
# Exported for use by other tools (like devt)
# Args: owner, current_word, description, [strip_owner_prefix (default: true)]
_gitc_autocomplete_github_repos() {
  local owner="$1"
  local current_word="$2"
  local description="$3"
  local strip_owner="${4:-true}"
  
  if [[ -z "$owner" ]]; then
    return 1
  fi
  
  local cache_file="${HOME}/.cache/gitc-${owner}-repos"
  local count_cache_file="${HOME}/.cache/gitc-${owner}-count"
  
  # Get cached repo count to decide between full listing vs search
  local repo_count=0
  if [[ -f "$count_cache_file" ]] && [[ $(($(date +%s) - $(stat -f %m "$count_cache_file" 2>/dev/null || stat -c %Y "$count_cache_file" 2>/dev/null))) -lt $GITC_CACHE_TIME ]]; then
    repo_count=$(cat "$count_cache_file" 2>/dev/null || echo "0")
  else
    # Use GitHub API to get repo count - much faster than fetching repos
    # Try user endpoint first, then org endpoint
    repo_count=$(gh api "users/$owner" --jq '.public_repos' 2>/dev/null || gh api "orgs/$owner" --jq '.public_repos' 2>/dev/null || echo "0")
    if [[ "$repo_count" -gt 0 ]]; then
      echo "$repo_count" > "$count_cache_file"
    fi
  fi
  
  # Decide whether to use full listing or incremental search
  if [[ $repo_count -gt $GITC_AUTOCOMPLETE_MAX_REPOS ]]; then
    # Use incremental search for large repos
    if [[ ${#current_word} -ge $GITC_AUTOCOMPLETE_MIN_SEARCH_CHARS ]]; then
      local -a search_results
      search_results=("${(@f)$(_search_github_repos "$owner" "$current_word" 50)}")
      
      if [[ ${#search_results[@]} -gt 0 ]]; then
        if [[ "$strip_owner" == "true" ]]; then
          # Strip owner prefix for cleaner completion
          local -a clean_results
          for repo in "${search_results[@]}"; do
            clean_results+=("${repo#*/}:$repo")
          done
          _describe "Search results for $description ($repo_count+ repos, showing matches for '$current_word')" clean_results
        else
          _describe "Search results for $description ($repo_count+ repos, showing matches for '$current_word')" search_results
        fi
      else
        _message "No matches found. Keep typing to search $description's $repo_count+ repos..."
      fi
    else
      _message "Type at least $GITC_AUTOCOMPLETE_MIN_SEARCH_CHARS characters to search $description's $repo_count+ repos"
    fi
  else
    # Fetch full list for smaller repos
    local -a user_repos
    user_repos=("${(@f)$(_fetch_github_repos "$owner" "$cache_file" "$GITC_CACHE_TIME" 1000)}")
    
    if [[ ${#user_repos[@]} -gt 0 ]]; then
      if [[ "$strip_owner" == "true" ]]; then
        # Strip owner prefix for cleaner completion
        local -a clean_repos
        for repo in "${user_repos[@]}"; do
          clean_repos+=("${repo#*/}:$repo")
        done
        _describe "$description repositories (${#user_repos[@]} repos)" clean_repos
      else
        _describe "$description repositories (${#user_repos[@]} repos)" user_repos
      fi
    else
      _message "No repositories found for $description"
    fi
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
  
  # Check if user is typing "username/" pattern
  if [[ "$current_word" == */* ]]; then
    local typed_user="${current_word%%/*}"
    local typed_query="${current_word#*/}"
    
    # Use shared autocomplete function with full repo names (don't strip owner)
    _gitc_autocomplete_github_repos "$typed_user" "$typed_query" "$typed_user" false
  else
    # Default to current user's repos
    local github_user=$(_get_github_user)
    if [[ -n "$github_user" ]]; then
      # Use shared autocomplete function with stripped owner prefix for cleaner display
      _gitc_autocomplete_github_repos "$github_user" "$current_word" "Your GitHub" true
    else
      _message "Install gh CLI and run: gh auth login"
    fi
  fi
}

compdef _gitc gitc


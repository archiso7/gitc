# gitc

A smart git clone wrapper that creates tmux sessions and organizes repositories by host/owner/repo.

## Features

- 🚀 **Smart cloning**: Automatically organizes repos into `~/src/host/owner/repo` structure
- 🪟 **Tmux integration** (optional): Creates a tmux session and cd's into the cloned directory if tmux is available
- 🎯 **GitHub shortcuts**: Just type `gitc my-repo` to clone your own repos
- 🌐 **Multi-host support**: Works with GitHub, GitLab, Bitbucket, or any git hosting service
- ⚡ **Auto-completion**: Tab completion for your GitHub repos and other users' repos
- 📦 **Standalone or library**: Can be used directly or as a dependency for other tools

## Installation

### As a submodule in your dotfiles

```bash
cd ~/.config/zsh
git submodule add <your-gitc-repo-url> gitc
```

### Standalone installation

```bash
git clone <your-gitc-repo-url> ~/.config/zsh/gitc
```

### Setup

Add to your `~/.zshrc`:

```zsh
# Load gitc
source ~/.config/zsh/gitc/gitc.zsh

# Optional: Configure directories
export GITC_CLONE_DIR="${HOME}/src"
export GITC_DEFAULT_HOST="github.com"
```

## Usage

### Basic Usage

```bash
# Clone your own repo (assumes current GitHub user)
gitc my-repo

# Clone from another user
gitc otheruser/their-repo

# Clone from any git host with full URL
gitc https://gitlab.com/user/project.git
gitc git@bitbucket.org:team/repo.git

# Pass additional git clone flags
gitc my-repo --depth 1
```

### Auto-completion

```bash
# Tab completion for your repos
gitc <TAB>

# Tab completion for another user's repos
gitc otheruser/<TAB>

# Smart incremental search for large orgs (1000+ repos)
gitc kubernetes/ku<TAB>  # Shows search results as you type
```

**Smart Autocomplete**: The completion system automatically detects large organizations or users with many repositories (500+ by default) and switches to **incremental search mode**. This makes autocomplete fast even for orgs with 10,000+ repos!

- **Small repos (<500)**: Shows full list of repos (cached for 1 hour)
- **Large repos (500+)**: Uses GitHub's search API as you type (minimum 2 characters)

**Tip**: For an even better completion experience with fuzzy search and preview, install [fzf-tab](https://github.com/Aloxaf/fzf-tab)!

### Directory Structure

Repositories are organized by host and owner:

```
~/src/
├── github.com/
│   ├── youruser/
│   │   ├── repo1/
│   │   └── repo2/
│   └── otheruser/
│       └── their-repo/
├── gitlab.com/
│   └── someuser/
│       └── project/
└── bitbucket.org/
    └── team/
        └── repo/
```

### Cache Management

```bash
# Refresh your repo cache manually
gitc-refresh-cache
```

Cache is automatically refreshed every hour.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `GITC_CLONE_DIR` | `${HOME}/src` | Base directory for cloned repos |
| `GITC_DEFAULT_HOST` | `github.com` | Default host for shortcuts |
| `GITC_AUTOCOMPLETE_MAX_REPOS` | `500` | Threshold for switching to search mode |
| `GITC_AUTOCOMPLETE_MIN_SEARCH_CHARS` | `2` | Minimum characters to type before searching |
| `GITC_CACHE_TIME` | `3600` | Cache lifetime in seconds (1 hour) |

### Customizing Autocomplete Behavior

```zsh
# In your ~/.zshrc, set these BEFORE sourcing gitc.zsh

# Use search mode for orgs with 200+ repos instead of 500
export GITC_AUTOCOMPLETE_MAX_REPOS=200

# Require 3 characters before triggering search
export GITC_AUTOCOMPLETE_MIN_SEARCH_CHARS=3

# Cache for 30 minutes instead of 1 hour
export GITC_CACHE_TIME=1800

source ~/.config/zsh/gitc/gitc.zsh
```

## Requirements

### Required
- `zsh`
- `git`
- `gh` (GitHub CLI) - for auto-completion and shortcuts

### Recommended
- `tmux` - For automatic session creation and management (gracefully degrades without it)
- [fzf-tab](https://github.com/Aloxaf/fzf-tab) - For enhanced fuzzy-search completion with preview windows

## Utilities for Other Tools

`gitc.zsh` exports several utility functions that other tools can use:

- `_tmux_session_with_command()` - Create tmux sessions with commands
- `_fetch_github_repos()` - Fetch and cache GitHub repos
- `_get_github_user()` - Get current GitHub user

See `devt.zsh` for an example of using gitc as a dependency.

## License

MIT


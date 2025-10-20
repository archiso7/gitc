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
```

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


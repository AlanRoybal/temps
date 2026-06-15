#!/usr/bin/env bash
# Claude Code status line — retro matrix green pixel bar

input=$(cat)

# --- Extract fields from JSON ---
model=$(echo "$input"        | jq -r '.model.display_name // "Claude"')
cwd=$(echo "$input"          | jq -r '.workspace.current_dir // .cwd // ""')
used_pct=$(echo "$input"     | jq -r '.context_window.used_percentage // empty')
five_hour=$(echo "$input"    | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_resets=$(echo "$input"  | jq -r '.rate_limits.five_hour.resets_at // empty')
seven_day=$(echo "$input"    | jq -r '.rate_limits.seven_day.used_percentage // empty')
seven_resets=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
vim_mode=$(echo "$input"     | jq -r '.vim.mode // empty')
session_name=$(echo "$input" | jq -r '.session_name // empty')
worktree_branch=$(echo "$input" | jq -r '.worktree.branch // empty')

# --- Date/time ---
now=$(date "+%H:%M:%S")

# --- Git branch (from cwd, skipping locks) ---
git_branch=""
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  git_branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
  if [ -z "$git_branch" ]; then
    git_branch=$(git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  fi
fi
[ -n "$worktree_branch" ] && git_branch="$worktree_branch"

# --- Shorten path (replace $HOME with ~) ---
home="$HOME"
short_cwd="${cwd/#$home/\~}"

# --- ANSI color codes ---
RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"
# Matrix green: bright green via 256-color
MATRIX="\033[38;5;46m"        # #00ff00 — vivid matrix green
MATRIX_DIM="\033[38;5;28m"    # darker green for empty bar cells
MATRIX_WARN="\033[38;5;214m"  # amber for >=50%
MATRIX_CRIT="\033[38;5;196m"  # red for >=80%
WHITE="\033[37m"
CYAN="\033[36m"
YELLOW="\033[33m"
MAGENTA="\033[35m"
BLUE="\033[34m"

# --- Retro pixel progress bar builder ---
# Usage: build_bar <percent_int> <bar_width>
# Renders: [████████░░░░░░░░░░░░] with matrix green filled, dim green empty
build_bar() {
  local pct=$1
  local width=$2
  local filled=$(( pct * width / 100 ))
  [ "$filled" -gt "$width" ] && filled=$width

  # Pick bar color based on fill level
  local bar_color
  if [ "$pct" -ge 80 ]; then
    bar_color="$MATRIX_CRIT"
  elif [ "$pct" -ge 50 ]; then
    bar_color="$MATRIX_WARN"
  else
    bar_color="$MATRIX"
  fi

  local bar=""
  local i=0
  while [ "$i" -lt "$filled" ]; do
    bar="${bar}█"
    i=$(( i + 1 ))
  done
  while [ "$i" -lt "$width" ]; do
    bar="${bar}░"
    i=$(( i + 1 ))
  done

  # Split filled / empty for coloring
  local filled_str="${bar:0:$filled}"
  local empty_str="${bar:$filled}"

  printf "${BOLD}${bar_color}%s${RESET}${MATRIX_DIM}%s${RESET}" \
    "$filled_str" "$empty_str"
}

# --- Countdown timer helper ---
# Usage: countdown_str <resets_at_epoch>
# Returns a human-readable "Xm" or "Xh Xm" string, empty if unavailable
countdown_str() {
  local resets_at=$1
  [ -z "$resets_at" ] && return
  local now_epoch
  now_epoch=$(date +%s)
  local diff=$(( resets_at - now_epoch ))
  [ "$diff" -le 0 ] && { echo "now"; return; }
  local hours=$(( diff / 3600 ))
  local mins=$(( (diff % 3600) / 60 ))
  if [ "$hours" -gt 0 ]; then
    echo "${hours}h${mins}m"
  else
    echo "${mins}m"
  fi
}

# ============================================================
# Build the status line
# ============================================================

# 1. Time (matrix green clock)
printf "${BOLD}${MATRIX}%s${RESET}" "$now"

# 2. Session name
if [ -n "$session_name" ]; then
  printf "  ${BOLD}${MAGENTA}%s${RESET}" "$session_name"
fi

# 3. Directory
printf "  ${CYAN}%s${RESET}" "$short_cwd"

# 4. Git branch
if [ -n "$git_branch" ]; then
  printf "  ${YELLOW}⎇ %s${RESET}" "$git_branch"
fi

# 5. Vim mode
if [ -n "$vim_mode" ]; then
  if [ "$vim_mode" = "INSERT" ]; then
    printf "  ${BOLD}${MATRIX}[INSERT]${RESET}"
  else
    printf "  ${BOLD}${BLUE}[NORMAL]${RESET}"
  fi
fi

# 6. Model (dim)
printf "  ${DIM}${WHITE}%s${RESET}" "$model"

# 7. Context window — retro pixel bar
if [ -n "$used_pct" ]; then
  used_int=$(printf "%.0f" "$used_pct")
  # Bar width: 20 cells
  BAR_WIDTH=20
  printf "  ${BOLD}${MATRIX}[${RESET}"
  build_bar "$used_int" "$BAR_WIDTH"
  printf "${BOLD}${MATRIX}]${RESET}"
  # Percentage label — color matches urgency
  if [ "$used_int" -ge 80 ]; then
    pct_color="$MATRIX_CRIT"
  elif [ "$used_int" -ge 50 ]; then
    pct_color="$MATRIX_WARN"
  else
    pct_color="$MATRIX"
  fi
  printf " ${BOLD}${pct_color}%d%%${RESET}" "$used_int"
else
  # No data yet — show idle bar placeholder
  printf "  ${BOLD}${MATRIX}[${RESET}${MATRIX_DIM}"
  i=0; while [ "$i" -lt 20 ]; do printf "░"; i=$(( i + 1 )); done
  printf "${RESET}${BOLD}${MATRIX}]${RESET} ${DIM}${WHITE}--%${RESET}"
fi

# 8. Rate limit timers (5-hour and 7-day) with countdown
rate_out=""
if [ -n "$five_hour" ]; then
  five_int=$(printf "%.0f" "$five_hour")
  timer=$(countdown_str "$five_resets")
  segment="5h:${five_int}%"
  [ -n "$timer" ] && segment="${segment} ↺${timer}"
  rate_out="$segment"
fi
if [ -n "$seven_day" ]; then
  seven_int=$(printf "%.0f" "$seven_day")
  timer=$(countdown_str "$seven_resets")
  segment="7d:${seven_int}%"
  [ -n "$timer" ] && segment="${segment} ↺${timer}"
  rate_out="${rate_out:+$rate_out  }$segment"
fi
if [ -n "$rate_out" ]; then
  printf "  ${DIM}${MATRIX_DIM}%s${RESET}" "$rate_out"
fi

printf "\n"

#!/bin/bash

# Tron-inspired Strategic Pipes Screensaver

# Terminal size
COLS=$(tput cols)
LINES=$(tput lines)

# Colors
declare -a COLORS=($(tput setaf 1) $(tput setaf 2) $(tput setaf 3) $(tput setaf 4) $(tput setaf 5) $(tput setaf 6) $(tput setaf 7) $(tput setaf 8))

# Pipe characters
PIPE_CHARS="┃┏ ┓┛━┓  ┗┃┛┗ ┏━"

# Directions: 0=up, 1=right, 2=down, 3=left
declare -a DX=(0 1 0 -1)
declare -a DY=(-1 0 1 0)

# Initialize pipes
num_pipes=8
declare -A grid
declare -a pipe_x
declare -a pipe_y
declare -a pipe_dir
declare -a pipe_next_dir
declare -a pipe_color
declare -a pipe_active
declare -a pipe_straight_count

CRASH_FRAMES=("💥" "🔥" "⚡" "🌟" "✨" "💨" " ")
declare -A crash_animations

init_pipes() {
    grid=()
    crash_animations=()
    local perimeter=$((2 * (COLS + LINES) - 4))
    local spacing=$((perimeter / num_pipes))

    for ((i=0; i<num_pipes; i++)); do
        local pos=$((i * spacing + RANDOM % spacing))
        if ((pos < COLS)); then
            pipe_x[i]=$pos
            pipe_y[i]=0
            pipe_dir[i]=2
        elif ((pos < COLS + LINES - 1)); then
            pipe_x[i]=$((COLS - 1))
            pipe_y[i]=$((pos - COLS + 1))
            pipe_dir[i]=3
        elif ((pos < 2 * COLS + LINES - 2)); then
            pipe_x[i]=$((2 * COLS + LINES - 3 - pos))
            pipe_y[i]=$((LINES - 1))
            pipe_dir[i]=0
        else
            pipe_x[i]=0
            pipe_y[i]=$((2 * (COLS + LINES) - 4 - pos))
            pipe_dir[i]=1
        fi
        pipe_next_dir[i]=${pipe_dir[i]}
        pipe_color[i]=${COLORS[$((RANDOM % ${#COLORS[@]}))]}
        pipe_active[i]=1
        pipe_straight_count[i]=0
        grid[${pipe_y[i]},${pipe_x[i]}]=1
    done
}

draw_pipe() {
    local x=$1
    local y=$2
    local color=$3
    local dir=$4
    local next_dir=$5
    local char_index=$((dir * 4 + next_dir))
    local char="${PIPE_CHARS:$char_index:1}"

    echo -ne "\e[${y};${x}H${color}${char}\e[0m"
    grid[$y,$x]=1
}

start_crash_animation() {
    local x=$1
    local y=$2
    crash_animations[$y,$x]=0
}

update_crash_animations() {
    local keys_to_remove=()

    for key in "${!crash_animations[@]}"; do
        local frame=${crash_animations[$key]}
        local y=${key%,*}
        local x=${key#*,}

        if ((frame < ${#CRASH_FRAMES[@]})); then
            echo -ne "\e[${y};${x}H${CRASH_FRAMES[$frame]}"
            ((crash_animations[$key]++))
        else
            keys_to_remove+=("$key")
        fi
    done

    for key in "${keys_to_remove[@]}"; do
        unset crash_animations[$key]
    done
}

check_collision() {
    local x=$1
    local y=$2
    if ((x < 0 || x >= COLS || y < 0 || y >= LINES)); then
        return 1
    fi
    if [[ -n "${grid[$y,$x]}" ]]; then
        return 1
    fi
    return 0
}

evaluate_move() {
    local x=$1
    local y=$2
    local dir=$3
    local score=0

    # Check ahead
    local ahead_x=$((x + DX[dir]))
    local ahead_y=$((y + DY[dir]))
    if check_collision $ahead_x $ahead_y; then
        ((score += 3))
        # Check two steps ahead
        ahead_x=$((ahead_x + DX[dir]))
        ahead_y=$((ahead_y + DY[dir]))
        if check_collision $ahead_x $ahead_y; then
            ((score += 2))
        fi
    fi

    # Check to the sides
    local left_dir=$(( (dir - 1 + 4) % 4 ))
    local right_dir=$(( (dir + 1) % 4 ))
    local left_x=$((x + DX[left_dir]))
    local left_y=$((y + DY[left_dir]))
    local right_x=$((x + DX[right_dir]))
    local right_y=$((y + DY[right_dir]))

    if check_collision $left_x $left_y; then
        ((score++))
    fi
    if check_collision $right_x $right_y; then
        ((score++))
    fi

    # Prefer moves that don't trap the pipe
    local back_dir=$(( (dir + 2) % 4 ))
    local back_x=$((x + DX[back_dir]))
    local back_y=$((y + DY[back_dir]))
    if ! check_collision $back_x $back_y; then
        ((score -= 2))
    fi

    echo $score
}

find_best_direction() {
    local x=$1
    local y=$2
    local current_dir=$3
    local best_dir=$current_dir
    local best_score=0

    for dir in 0 1 2 3; do
        local new_x=$((x + DX[dir]))
        local new_y=$((y + DY[dir]))
        if check_collision $new_x $new_y; then
            local score=$(evaluate_move $new_x $new_y $dir)
            if ((dir == current_dir)); then
                ((score += 2))  # Favor continuing straight
            elif ((dir == (current_dir + 2) % 4)); then
                ((score -= 4))  # Penalize 180-degree turns
            fi
            if ((score > best_score || (score == best_score && RANDOM % 2 == 0))); then
                best_score=$score
                best_dir=$dir
            fi
        fi
    done

    # Occasionally make a random move
    if ((RANDOM % 30 == 0)); then
        local random_dir=$((RANDOM % 4))
        local new_x=$((x + DX[random_dir]))
        local new_y=$((y + DY[random_dir]))
        if check_collision $new_x $new_y; then
            best_dir=$random_dir
        fi
    fi

    echo $best_dir
}

move_pipes() {
    for ((i=0; i<num_pipes; i++)); do
        if ((pipe_active[i] == 1)); then
            local current_x=${pipe_x[i]}
            local current_y=${pipe_y[i]}
            local current_dir=${pipe_dir[i]}
            
            # Find the best direction
            local next_dir=$(find_best_direction $current_x $current_y $current_dir)
            
            local new_x=$((current_x + DX[next_dir]))
            local new_y=$((current_y + DY[next_dir]))
            
            if check_collision $new_x $new_y; then
                draw_pipe $current_x $current_y ${pipe_color[i]} $current_dir $next_dir
                pipe_x[i]=$new_x
                pipe_y[i]=$new_y
                pipe_dir[i]=$next_dir
                pipe_next_dir[i]=$next_dir
                if ((next_dir == current_dir)); then
                    ((pipe_straight_count[i]++))
                else
                    pipe_straight_count[i]=0
                fi
            else
                start_crash_animation $current_x $current_y
                pipe_active[i]=0
            fi
        fi
    done
}

check_game_over() {
    local active_count=0
    for ((i=0; i<num_pipes; i++)); do
        if ((pipe_active[i] == 1)); then
            ((active_count++))
        fi
    done
    if ((active_count <= 1)); then
        return 0
    fi
    return 1
}

run_screensaver() {
    # Hide cursor
    echo -ne "\e[?25l"
    
    while true; do
        echo -ne "\e[2J"
        init_pipes
        while true; do
            move_pipes
            update_crash_animations
            sleep 0.05
            if check_game_over && [ ${#crash_animations[@]} -eq 0 ]; then
                sleep 2  # Pause to show the final state
                break
            fi
        done
    done
}

# Trap to ensure cursor is shown when the script exits
trap 'echo -ne "\e[?25h"' EXIT

# Redirect stderr to /dev/null to suppress error messages
exec 2>/dev/null

run_screensaver
#!/bin/sh
# shellcheck disable=SC1090 disable=SC3043
# SC1090: ShellCheck can't follow non-constant source. Use a directive to specify location.

# set -o errexit
set -o nounset

### Configuration ###
TAPE_CONF="/etc/tape/tape.conf"
TAPE_SCRIPTS_DIR="/etc/tape/scripts.d"

[ -f "$TAPE_CONF" ] || (echo "error: the config file $TAPE_CONF does not exist" >&2 && exit 1)
. "$TAPE_CONF"

### Arguments ###

dry_run=false
restic_dry_run=""
verbose=false

### Error handling and logging ###

errors=""

log() {
    if $verbose; then
        echo "$1"
    fi
}

error() {
    what=$1
    errors="$errors
$what"

    echo "$what" >&2
}

fail() {
    local message="$1"

    error "$message" >&2

    exit 1
}

check_config() {
    local commands="restic rclone"
    
    for command in $commands; do
        if ! command -v "$command" > /dev/null; then
            fail "error: $command is not installed"
        fi
    done

    if [ ! -f "$TAPE_KEY_PATH" ]; then
        fail "error: the key file $TAPE_KEY_PATH does not exist"
    fi
}

### Run ###

print_usage() {
    echo "
  tape [OPTIONS] COMMAND

  Backup the system using custom scripts and restic.

  Options:
    -h, --help     Print this help message
    -n, --dry-run  Print what would be done without doing it
    -v, --verbose  Print more information

  Commands:
    init             Initialize the backup repository
    backup [SCRIPT]  Backup the system using the given script
                     (default: *)
    report           Report the repository status to stdout
  
  Configuration:
    The configuration file is located at $TAPE_CONF. 
    It should contain the following variables:

    TAPE_KEY_PATH
    TAPE_REPO
    TAPE_EXCLUDE
    TAPE_KEEP_LAST_N
    "
}

process_flags() {
    for flag in "$@"; do
        case "$flag" in
            -h|--help)
                print_usage
                exit 0
                ;;
            -n|--dry-run)
                dry_run=true
                restic_dry_run="--dry-run"
                ;;
            -v|--verbose)
                verbose=true
                ;;
            -*)
                fail "unknown flag: $flag, try tape --help"
                ;;
        esac
    done
}

process_args() {
    if [ $# -eq 0 ]; then
        print_usage
        exit 1
    fi

    while [ $# -gt 0 ]
    do
        case $1 in
            -*) ;;
            init) 
                local repo="${2:-$TAPE_REPO}"
                init "$repo"
                
                exit 0 
            ;;
            backup)
                local backup_script="${2:-*}"
                backup "$backup_script"

                exit 0
            ;;
            report)
                local repo="${2:-*}" 
                report "$repo";

                exit 0
            ;;
            *) print_usage; exit 1 ;;
        esac
        shift
    done
}

### Commands ###

init() {
    local repo="$1"

    echo "Initializing the backup repository at $repo"

    # Cannot use --dry-run here.
    restic cat config --repo "$repo" --password-file "$TAPE_KEY_PATH" > /dev/null 2>&1
    result=$?

    if [ $result -eq 0 ]; then
        error "error: backup repository $repo already initialized"
        return 1
    fi

    if ! $dry_run; then
        restic init $restic_dry_run --password-file "$TAPE_KEY_PATH" --repo "$repo" \
            || fail "error: restic init failed" false
    fi

    echo "Backup repository initialized"
}

backup() {
    script_name=$1

    start=$(date +%s)

    if [ "$script_name" = "*" ]; then
        log "Running all backup scripts at $TAPE_SCRIPTS_DIR"
    elif [ ! -f "$TAPE_SCRIPTS_DIR/$script_name" ]; then
        fail "backup script $script_name does not exists"
    fi

    for script in $TAPE_SCRIPTS_DIR/$script_name; do
        log "Running $script"

        if [ ! -x "$script" ]; then
            log "Skipping not executable $(basename "$script")"
            continue
        fi

        run_script "$script"
    done
    
    local time_string="unknown"
    time_string=$(duration_string "$start")

    local message="Backup complete in $time_string."
    message="$message

    $(report "*")" || fail "error: report failed"

    if [ -n "${TAPE_KEEP_LAST_N}" ]; then
        forget_backups
    fi

    if [ -n "$errors" ]; then
        return 1
    fi

    echo
}

run_script() {
    local script="$1"

    before() { true; }
    after() { true; }

    . "$script"

    out_file="$(mktemp)"
    {
        [ $dry_run = true ] && set -v 
        [ $dry_run = false ] && set -x

        before
        result=$?
        
        [ $dry_run = false ] && set +x
        [ $dry_run = true ] && set +v

    } > "$out_file" 2>&1
    out="$(cat "$out_file")"

    [ $dry_run = true ] && echo "$script"

    files=${files:-""}
    repository=${repository:-"$TAPE_REPO"}
    
    log "Backing up $files to $repository"

    local exclude="${TAPE_EXCLUDE:-}"
    local exclude_flags=""
    for item in $exclude; do
        exclude_flags="$exclude_flags --exclude $item"
    done

    for location in $repository; do
        if [ -z "$files" ]; then
            # no files to backup
            break
        fi

        restic backup $restic_dry_run \
            --password-file "$TAPE_KEY_PATH" \
            --repo "$location" $exclude_flags $files \
            || error "error: $(basename "$script"): restic backup $files failed"
    done

    {
        [ $dry_run = true ] && set -v
        [ $dry_run = false ] && set -x
        
        after
        result=$?
        
        [ $dry_run = false ] && set +x
        [ $dry_run = true ] && set +v

    } >> "$out_file" 2>&1
    out="$(cat "$out_file")"
    rm -f "$out_file"

    if [ ! $result -eq 0 ]; then
        error "error: script $(basename "$script") failed"
        error "$out"

        return $result
    fi
}

# PARAMS
#   $1  "*" for all, or repository name
report() {
    local repositories_list
    repositories_list="$(collect_repositories "$1")"

    local first_run=true
    for location in $repositories_list; do
        if ! $first_run; then
            echo ""
        fi
        printf "%s" "Backup stats for $location: "
        restic stats --mode raw-data \
            --password-file "$TAPE_KEY_PATH" \
            --repo "$location" \
            --quiet \
            || fail "error: could not get stats for $location"

        first_run=false
    done
}

### Utils ###

# Collects all repositories from the scripts
# 
# PARAMS
#   $1  empty for all, or repository name
collect_repositories() {
    local repositories_list="${1:-*}"

    if [ "$repositories_list" = "*" ]; then
        repositories_list="$TAPE_REPO"

        # Aggregates all repositories
        for script in "$TAPE_SCRIPTS_DIR"/*; do
            . "$script"

            # Sourced from script, or default to TAPE_REPO
            local repository="${repository-$TAPE_REPO}"
            local collected_repositories=""

            for location in $repository; do
                local found=false
                for known_location in $repositories_list; do
                    if [ "$location" = "$known_location" ]; then
                        found=true
                    fi
                done

                if ! $found; then
                    collected_repositories="$collected_repositories $location"
                fi
            done

            repositories_list="$repositories_list $collected_repositories"
        done
    fi

    echo "$repositories_list"
}

forget_backups() {
    local repositories_list
    repositories_list="$(collect_repositories)"

    for location in $repositories_list; do
        restic forget $restic_dry_run \
            --password-file "$TAPE_KEY_PATH" \
            --repo "$location" \
            --keep-last "$TAPE_KEEP_LAST_N" \
            --prune \
            || error "error: restic forget failed for $location"
    done
}

duration_string() {
    local start="$1"
    end=$(date +%s)

    local runtime=$((end-start))
    local hours=$((runtime / 3600))
    local minutes=$(( (runtime % 3600) / 60 )) 
    local seconds=$(( (runtime % 3600) % 60 ))
    
    printf "%02d:%02d:%02d" $hours $minutes $seconds
}

### Main ###
log "Running tape"

process_flags "$@"

check_config

process_args "$@"

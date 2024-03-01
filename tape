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
restic_flags=""
rclone_flags=""

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
    errors="$errors\n$what"
    echo "$what" >&2
}

fail() {
    error "$1" >&2
    send_email "Backup failed!" "$errors"
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
    report           Report the backup status to \$TAPE_REPORT_EMAIL
  
  Configuration:
    The configuration file is located at $TAPE_CONF. 
    It should contain the following variables:

    TAPE_KEY_PATH
    TAPE_REPO
    TAPE_EXCLUDE
    TAPE_KEEP_LAST_N
    TAPE_REPORT_EMAIL
    "
}

process_flags() {
    restic_flags="--password-file $TAPE_KEY_PATH"

    for flag in "$@"; do
        case "$flag" in
            -h|--help)
                print_usage
                exit 0
                ;;
            -n|--dry-run)
                dry_run=true
                restic_flags="$restic_flags --dry-run"
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
    local repo=$1

    echo "Initializing the backup repository at $repo"

    # Cannot use --dry-run here.
    restic cat config --repo "$repo" --password-file "$TAPE_KEY_PATH" 2> /dev/null
    result=$?

    if [ $result -eq 0 ]; then
        error "error: backup repository already initialized"
        return 1
    fi

    if ! $dry_run; then
        restic init --repo "$repo" $restic_flags \
            || fail "error: restic init failed"
    fi

    echo "Backup repository initialized"
}

backup() {
    script_name=$1

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

    local message
    message=$(report "*") || fail "error: report failed"
    
    local repositories_list
    repositories_list="$(collect_repositories)"

    for location in $repositories_list; do
        restic forget --repo "$location" --keep-last $TAPE_KEEP_LAST_N $restic_flags --prune \
            || fail "error: restic forget failed"
    done

    send_email "$message" "$errors"
}

run_script() {
    local script="$1"

    out_file="$(mktemp)"
    {
        before() { true; }

        [ $dry_run = true ] && set -v
        [ $dry_run = false ] && set -x
        
        . "$script" && before
        result=$?
        
        [ $dry_run = false ] && set +x
        [ $dry_run = true ] && set +v

    } > "$out_file" 2>&1
    out="$(cat "$out_file")"
    rm -f "$out_file"

    [ $dry_run = true ] && echo "$script"

    if [ ! $result -eq 0 ]; then
        error "$out"
        error "error: $(basename "$script") failed"

        return $result
    fi

    files=${files:-""}
    repository=${repository:-"$TAPE_REPO"}
    
    log "Backing up $files"
    log "to $repository"

    for location in $repository; do
        restic backup --repo "$location" $restic_flags "$files" \
            || fail "error: restic failed"
    done
}

report() {
    local repositories_list
    repositories_list="$(collect_repositories "$1")"

    local stats=""
    for location in $repositories_list; do
        local newline=""
        [ -z "$stats" ] || newline="\n\n"
        stats="$stats$newline"$({
            printf "%s: " "$location"
            restic stats --quiet --repo "$location" $restic_flags \
                || fail "error: restic report failed"
        })
    done

    # Use printf to ensure the \n is interpreted as a newline
    printf "$stats\n"
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

send_email() {
    local body="$1"
    local errors="${2:-}"

    local subject="Tape backup report"
    if [ -n "$errors" ]; then
        subject="[Attention required] $subject"
        body="$body\n\n$errors"
    fi

    local address="${TAPE_REPORT_EMAIL:-}"
    if [ -n "$address" ] && command -v mail > /dev/null; then
        printf "$body\n" | mail -s "$subject" "$address" \
            && log "Report sent to $address"
    else
        printf "$body\n"
    fi
}

### Main ###
log "Running tape"

check_config

process_flags "$@"
process_args "$@"

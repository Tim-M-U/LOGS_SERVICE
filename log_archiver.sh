#!/usr/bin/env bash
set -uo pipefail

LOGS_DIR="${1:-/LOGS}"
THRESHOLD="${2:-90}"
COMPONENTS=(auth_service data_process_service system_event_handler_service)
KEEP_NEWEST=1
LOG_NAME_REGEX='^.+_[0-9]{4}_[0-9]{2}_[0-9]{2}_[0-9]+\.log$'

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
die() { log "ERROR: $*" >&2; exit 1; }
mb() { echo "$(( $1 / 1024 / 1024 ))M"; }

dir_usage_bytes() {
    du -s --block-size=1 "$1" | cut -f1
}

timestamp_of() {
    local name="$1" ts
    ts="${name##*_}"
    echo "${ts%.log}"
}

list_logs_oldest_first() {
    local dir="$1" path name
    for path in "$dir"/*.log; do
        [[ -f "$path" ]] || continue
        name="${path##*/}"
        [[ "$name" =~ $LOG_NAME_REGEX ]] || continue
        echo "$(timestamp_of "$name") $name"
    done | sort -n | cut -d' ' -f2-
}

archive_dir() {
    local dir="$1" limit="$2"
    local component size need freed f fsize first_ts last_ts archive new_size
    local -a files candidates batch

    component="$(basename "$dir")"
    size="$(dir_usage_bytes "$dir")"

    while (( size > limit )); do
        mapfile -t files < <(list_logs_oldest_first "$dir")

        if (( ${#files[@]} <= KEEP_NEWEST )); then
            log "  [$component] WARNING: still over limit, but only the current log is left"
            return 0
        fi

        candidates=("${files[@]:0:${#files[@]}-KEEP_NEWEST}")
        need=$(( size - limit ))

        batch=()
        freed=0
        for f in "${candidates[@]}"; do
            batch+=("$f")
            fsize="$(stat -c %s "$dir/$f")"
            freed=$(( freed + fsize ))
            if (( freed >= need )); then
                break
            fi
        done

        first_ts="$(timestamp_of "${batch[0]}")"
        last_ts="$(timestamp_of "${batch[-1]}")"
        archive="$dir/${component}_archive_${first_ts}_${last_ts}.tar.gz"

        log "  [$component] archiving ${#batch[@]} file(s), $(mb "$freed") -> ${archive##*/}"

        if tar -czf "$archive" -C "$dir" -- "${batch[@]}" && tar -tzf "$archive" > /dev/null; then
            for f in "${batch[@]}"; do
                rm -f -- "$dir/$f"
            done
        else
            rm -f -- "$archive"
            log "  [$component] ERROR: failed to create archive, original files kept"
            return 1
        fi

        new_size="$(dir_usage_bytes "$dir")"
        if (( new_size >= size )); then
            log "  [$component] WARNING: archiving did not reduce folder size, stopping"
            return 1
        fi
        size="$new_size"
    done

    log "  [$component] now uses $(mb "$size"), within limit"
    return 0
}

if ! [[ "$THRESHOLD" =~ ^[0-9]+$ ]] || (( THRESHOLD < 1 || THRESHOLD > 100 )); then
    die "threshold must be an integer from 1 to 100, got '$THRESHOLD'"
fi
[[ -d "$LOGS_DIR" ]] || die "directory $LOGS_DIR does not exist"
mountpoint -q "$LOGS_DIR" || die "$LOGS_DIR is not a mount point"

read -r fs_size fs_used < <(df --block-size=1 --output=size,used "$LOGS_DIR" | tail -n 1)
log "$LOGS_DIR: used $(mb "$fs_used") of $(mb "$fs_size") ($(( fs_used * 100 / fs_size ))%), threshold ${THRESHOLD}%"

if (( fs_used * 100 <= fs_size * THRESHOLD )); then
    log "threshold not exceeded, nothing to do"
    exit 0
fi

total_limit=$(( fs_size * THRESHOLD / 100 ))
per_dir_limit=$(( total_limit / ${#COMPONENTS[@]} ))
log "threshold exceeded, limit per folder: $(mb "$per_dir_limit")"

archived_any=0
exit_code=0
for component in "${COMPONENTS[@]}"; do
    dir="$LOGS_DIR/$component"
    if [[ ! -d "$dir" ]]; then
        log "  [$component] folder not found, skipping"
        continue
    fi

    dir_size="$(dir_usage_bytes "$dir")"
    if (( dir_size > per_dir_limit )); then
        log "  [$component] uses $(mb "$dir_size"), over limit"
        archive_dir "$dir" "$per_dir_limit" || exit_code=1
        archived_any=1
    else
        log "  [$component] uses $(mb "$dir_size"), within limit"
    fi
done

if (( archived_any == 0 )); then
    log "WARNING: partition is over threshold, but no folder exceeds its share"
fi

read -r fs_size fs_used < <(df --block-size=1 --output=size,used "$LOGS_DIR" | tail -n 1)
log "done: used $(mb "$fs_used") of $(mb "$fs_size") ($(( fs_used * 100 / fs_size ))%)"
exit "$exit_code"

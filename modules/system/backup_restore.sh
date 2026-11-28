#!/bin/sh

# Config Backup and Restore Module for DayPass Deployment Stack
# Preserves critical UCI configurations during updates and system migration

BACKUP_DIR="/tmp/daypass/backups"
CONFIG_PATHS="/etc/config/passwall /etc/config/passwall2 /etc/config/xray /etc/config/sing-box /etc/config/niki"

# Creates a compressed timestamped archive of target configuration files
backup_configs()
(
    umask 077
    local dir path stage archive latest target metadata owner
    owner=$(id -u) || return 1
    [ "$BACKUP_DIR" = /tmp/daypass/backups ] || return 1
    for dir in /tmp/daypass "$BACKUP_DIR"; do
        [ -d "$dir" ] || mkdir "$dir" || return 1
        [ ! -L "$dir" ] || return 1
        metadata=$(LC_ALL=C ls -ldn "$dir") || return 1
        case "$metadata" in
            d[r-][w-][x-][r-]-[x-][r-]-[x-]\ *) ;;
            *) return 1 ;;
        esac
        [ "$(printf '%s\n' "$metadata" | awk 'NR == 1 { print $3 }')" = "$owner" ] || return 1
    done
    [ ! -L /etc/config ] || return 1
    set --
    for path in $CONFIG_PATHS; do
        case "$path" in /etc/config/passwall|/etc/config/passwall2|/etc/config/xray|/etc/config/sing-box|/etc/config/niki) ;; *) return 1 ;; esac
        [ ! -L "$path" ] || return 1
        [ -e "$path" ] || continue
        [ -f "$path" ] || return 1
        metadata=$(LC_ALL=C ls -ldn "$path") || return 1
        [ "$(printf '%s\n' "$metadata" | awk 'NR == 1 { print $2 }')" = 1 ] &&
            [ "$(wc -c < "$path")" -le 8388608 ] || return 1
        set -- "$@" "${path#/}"
    done
    [ "$#" -gt 0 ] || { echo "No engine configs to back up."; return 0; }
    latest="$BACKUP_DIR/latest_backup.tar.gz"
    if [ -L "$latest" ]; then
        target=$(readlink "$latest") || return 1
        case "$target" in "$BACKUP_DIR"/daypass_config_backup_*.tar.gz)
            [ "${target%/*}" = "$BACKUP_DIR" ] && [ ! -d "$latest" ] || return 1 ;;
            *) return 1 ;;
        esac
    elif [ -e "$latest" ]; then
        echo "Latest backup path already occupied." >&2
        return 1
    fi
    stage=$(mktemp -d "$BACKUP_DIR/.backup.XXXXXX") || return 1
    trap 'rm -rf "$stage"' EXIT
    archive="$BACKUP_DIR/daypass_config_backup_$(date +%Y%m%d_%H%M%S)_${stage##*.}.tar.gz"
    tar -czf "$stage/archive" -C / "$@" && gzip -t "$stage/archive" &&
        tar -tzf "$stage/archive" >/dev/null || return 1
    # A hard link publishes the complete archive without replacing an older file.
    [ ! -e "$archive" ] && [ ! -L "$archive" ] && ln "$stage/archive" "$archive" || return 1
    ln -s "$archive" "$stage/latest" && mv -f "$stage/latest" "$latest" || {
        echo "Backup saved at $archive; could not update latest." >&2
        return 1
    }
    echo "Backup saved to $archive"
)

# Read physical tar headers; tar listings may normalize paths or hide extension
# records. Only offsets of exact, ordinary config files leave this parser.
_restore_tar_index()
{
    LC_ALL=C awk -v bytes="$1" '
    BEGIN { pos=0; block=0 }
    function octal(start, width,    i,v,n,endfield) {
        n=0
        for (i=start; i<start+width; i++) {
            v=h[i]
            if (v>=48 && v<=55 && !endfield) n=n*8+v-48
            else if (v==0 || v==32) endfield=1
            else return -1
        }
        return n
    }
    function header(    i,sum,name,size) {
        sum=0
        for (i=0;i<512;i++) sum+=h[i]
        if (!sum) { zeros++; return }
        if (zeros || (h[156]!=0 && h[156]!=48)) exit 1
        for (i=148;i<156;i++) sum+=32-h[i]
        if (sum!=octal(148,8)) exit 1
        for (i=0;i<100 && h[i];i++) name=name sprintf("%c",h[i])
        for (;i<100;i++) if (h[i]) exit 1
        if (name !~ /^etc\/config\/(passwall|passwall2|xray|sing-box|niki)$/ || seen[name]++) exit 1
        # No linkname, ustar prefix or GNU sparse/extension metadata.
        for (i=157;i<257;i++) if (h[i]) exit 1
        for (i=345;i<512;i++) if (h[i]) exit 1
        size=octal(124,12)
        if (size<0 || size>8388608) exit 1
        sub(/^etc\/config\//,"",name)
        print name, block+1, size
        members++
        payload=int((size+511)/512)
        remaining=size
    }
    {
        for (j=1;j<=NF;j++) {
            if (!payload) h[pos]=$j+0
            else if (remaining>0) remaining--
            else if ($j!=0) exit 1
            if (++pos==512) {
                if (payload) payload--
                else header()
                pos=0; block++
            }
        }
    }
    END { if (block*512!=bytes || !members || pos || payload || zeros<2) exit 1 }
    '
}

_restore_rollback()
{
    local pkg
    for pkg in passwall passwall2 xray sing-box niki; do
        if [ -f "$txn/original/$pkg" ]; then
            cp -p "$txn/original/$pkg" "$txn/replacement" &&
                mv -f "$txn/replacement" "$config/$pkg" || return 1
        elif [ -f "$txn/absent/$pkg" ]; then
            rm -f "$config/$pkg" || return 1
        fi
    done
    sync && rm "$txn/active" && sync
}

restore_configs()
(
    umask 077
    local archive="${1:-$BACKUP_DIR/latest_backup.tar.gz}" config=/etc/config
    local txn="$config/.daypass-restore" work pkg block size bytes failed=0
    [ -d "$config" ] && [ ! -L "$config" ] || return 1
    # Lock the directory inode itself; no stale PID file or removable lock.
    exec 9< "$config" || return 1
    flock -n 9 || { echo "Restore needs flock and exclusive access to the configuration directory." >&2; return 1; }
    if [ -e "$txn" ] || [ -L "$txn" ]; then
        [ -d "$txn" ] && [ ! -L "$txn" ] || return 1
        if [ ! -f "$txn/owner" ]; then
            rmdir "$txn" || { echo "Unrecognized restore directory; inspect $txn." >&2; return 1; }
        elif [ -f "$txn/active" ]; then
            _restore_rollback || { echo "Recovery incomplete; original files retained in $txn." >&2; return 1; }
            rm -rf "$txn" || return 1
            echo "Interrupted restore rolled back. Review the configs before retrying." >&2
            return 1
        fi
        rm -rf "$txn" || return 1
    fi
    [ -f "$archive" ] || { echo "Backup archive unavailable." >&2; return 1; }
    work=$(mktemp -d) || return 1
    trap 'rm -rf "$work"; if [ ! -f "$txn/active" ]; then rm -rf "$txn"; fi' EXIT
    trap 'exit 1' HUP INT TERM
    # Cap decompressed input (48 MiB, using POSIX 512-byte file limit units).
    (ulimit -f 98304 && gzip -dc < "$archive" > "$work/archive") || return 1
    bytes=$(wc -c < "$work/archive") || return 1
    [ "$bytes" -le 50331648 ] || return 1
    if command -v od >/dev/null 2>&1; then
        od -An -v -tu1 "$work/archive" | _restore_tar_index "$bytes" > "$work/index" || return 1
    else
        hexdump -v -e '16/1 "%u " "\n"' "$work/archive" | _restore_tar_index "$bytes" > "$work/index" || return 1
    fi
    mkdir "$work/new" "$work/delta" "$txn" || return 1
    touch "$txn/owner" || return 1
    mkdir "$txn/original" "$txn/absent" || return 1
    while read -r pkg block size; do
        case "$pkg" in passwall|passwall2|xray|sing-box|niki) ;; *) return 1 ;; esac
        # A secondary UCI config can shadow the staged or restored file.
        if [ -e "/var/run/uci/$pkg" ] || [ -L "/var/run/uci/$pkg" ]; then
            echo "Active runtime override for $pkg; restore cancelled." >&2
            return 1
        fi
        if [ -e "/tmp/.uci/$pkg" ] || [ -L "/tmp/.uci/$pkg" ]; then
            echo "Pending UCI state for $pkg; resolve it before restoring." >&2
            return 1
        fi
        dd if="$work/archive" bs=512 skip="$block" count="$(((size+511)/512))" of="$work/blocks" 2>/dev/null &&
            head -c "$size" "$work/blocks" > "$work/new/$pkg" || return 1
        [ "$(wc -c < "$work/new/$pkg")" -eq "$size" ] || return 1
        LC_ALL=C tr -d '\000' < "$work/new/$pkg" > "$work/text" &&
            cmp -s "$work/text" "$work/new/$pkg" || return 1
        uci -s -c "$work/new" -t "$work/delta" export "$pkg" > "$work/$pkg.export" || return 1
        [ ! -L "$config/$pkg" ] || return 1
        if [ -e "$config/$pkg" ]; then
            [ -f "$config/$pkg" ] || return 1
            local pending
            pending=$(uci changes "$pkg") || return 1
            [ -z "$pending" ] || { echo "Pending UCI changes for $pkg." >&2; return 1; }
            cp -p "$config/$pkg" "$txn/original/$pkg" || return 1
        else
            touch "$txn/absent/$pkg" || return 1
        fi
    done < "$work/index"
    sync && touch "$txn/active" && sync || return 1
    while read -r pkg block size; do
        if [ -f "$txn/original/$pkg" ]; then
            cp -p "$txn/original/$pkg" "$txn/replacement" || { failed=1; break; }
        fi
        cat "$work/new/$pkg" > "$txn/replacement" &&
            mv -f "$txn/replacement" "$config/$pkg" &&
            uci -s -c "$config" -t "$work/delta" commit "$pkg" &&
            uci -s -c "$config" -t "$work/delta" export "$pkg" > "$work/live.export" &&
            cmp -s "$work/$pkg.export" "$work/live.export" || { failed=1; break; }
    done < "$work/index"
    if [ "$failed" = 1 ]; then
        _restore_rollback || { echo "Rollback incomplete; originals retained in $txn." >&2; return 1; }
        echo "Restore failed; original configuration restored." >&2
        return 1
    fi
    sync && rm "$txn/active" && sync || return 1
    echo "Configuration restore completed."
)

# Standalone execution handler
case "$0" in
    *backup_restore.sh)
        case "${1:-backup}" in
            backup)  backup_configs ;;
            restore) restore_configs "$2" ;;
        esac
        ;;
esac
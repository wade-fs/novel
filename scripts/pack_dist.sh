#!/usr/bin/env bash
# novel/scripts/pack_dist.sh
# 將小說目錄的 chapters/ 與 book.yaml(.yml) 打包成 <book_id>.zip，
# 只有在該目錄內容有更新（git commit 時間與 .timestamp 不同）時才重新打包。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOVEL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"   # scripts/ 的上一層，即所有小說所在的根目錄
BOOK_ARGS=()
DIST_DIR=""
FORCE=0

usage() {
    cat <<USAGE
Usage: $(basename "$0") [-d <book_dir>]... [-t <dist_dir>] [-f] [-h]
  -d <book_dir>  只打包指定的小說目錄，可重複使用 (例: -d one-space -d song)
                 相對路徑先以目前目錄解析，找不到再以 $NOVEL_ROOT 解析
                 未指定時，打包 $NOVEL_ROOT 底下所有含 chapters/ 的目錄
  -t <dist_dir>  指定輸出目錄
                 預設: $NOVEL_ROOT/../novel-reader/app/src/main/assets/novels
                 若該目錄不存在則用 $NOVEL_ROOT/dist
  -f             強制重新打包
  -h             顯示說明
USAGE
}

die() { echo "Error: $*" >&2; exit 1; }

while getopts "d:t:fh" opt; do
    case "$opt" in
        d) BOOK_ARGS+=("$OPTARG") ;;
        t) DIST_DIR="$OPTARG" ;;
        f) FORCE=1 ;;
        h) usage; exit 0 ;;
        *) usage >&2; exit 1 ;;
    esac
done

command -v zip >/dev/null 2>&1 || die "找不到 zip，請先安裝。"
command -v git >/dev/null 2>&1 || die "找不到 git，請先安裝。"

# ---- 決定要打包哪些小說目錄 ----
BOOK_DIRS=()
if (( ${#BOOK_ARGS[@]} > 0 )); then
    for arg in "${BOOK_ARGS[@]}"; do
        if [[ -d "$arg" ]]; then
            dir="$(cd "$arg" && pwd)"
        elif [[ -d "$NOVEL_ROOT/$arg" ]]; then
            dir="$(cd "$NOVEL_ROOT/$arg" && pwd)"
        else
            die "Book directory '$arg' does not exist."
        fi
        [[ -d "$dir/chapters" ]] || die "'$dir' 底下沒有 chapters/，不是小說目錄。"
        BOOK_DIRS+=("$dir")
    done
else
    for dir in "$NOVEL_ROOT"/*/; do
        dir="${dir%/}"
        [[ -d "$dir/chapters" ]] && BOOK_DIRS+=("$dir")
    done
fi

# ---- 決定輸出目錄 ----
if [[ -z "$DIST_DIR" ]]; then
    assets_dir="$NOVEL_ROOT/../novel-reader/app/src/main/assets/novels"
    if [[ -d "$assets_dir" ]]; then
        DIST_DIR="$assets_dir"
    else
        DIST_DIR="$NOVEL_ROOT/dist"
    fi
fi
mkdir -p "$DIST_DIR"
DIST_DIR="$(cd "$DIST_DIR" && pwd)"

# 暫存目錄放在輸出目錄內，確保 mv 為同一檔案系統上的原子操作
TMP_DIR="$(mktemp -d "$DIST_DIR/.pack.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Target output directory: $DIST_DIR"

git_dirty() {   # git_dirty <book_dir> <path>...
    local book_dir="$1"; shift
    [[ -n "$(git -C "$book_dir" status --porcelain -- "$@" 2>/dev/null || true)" ]]
}

git_latest_ts() {   # git_latest_ts <book_dir> <path>...  (無紀錄時輸出 0)
    local book_dir="$1" ts; shift
    ts="$(git -C "$book_dir" log -1 --format=%ct -- "$@" 2>/dev/null || true)"
    echo "${ts:-0}"
}

# 判斷是否需要重新打包；需要時輸出原因並回傳 0
needs_pack() {   # needs_pack <book_dir> <out_zip> <ts_file> <path>...
    local book_dir="$1" out_zip="$2" ts_file="$3"; shift 3

    (( FORCE )) && { echo "forced"; return 0; }
    [[ -f "$out_zip" ]] || { echo "zip missing"; return 0; }
    [[ -f "$ts_file" ]] || { echo "no timestamp"; return 0; }
    git_dirty "$book_dir" "$@" && { echo "uncommitted changes"; return 0; }

    local latest_ts saved_ts
    latest_ts="$(git_latest_ts "$book_dir" "$@")"
    [[ "$latest_ts" == 0 ]] && { echo "no git history"; return 0; }

    saved_ts="$(tr -d '[:space:]' < "$ts_file")"
    [[ "$saved_ts" =~ ^[0-9]+$ ]] || saved_ts=0

    # 用 != 而非 -gt：切換分支或回到較舊的 commit 時，時間變小也要重打包
    [[ "$latest_ts" != "$saved_ts" ]] && { echo "git commit changed"; return 0; }
    return 1
}

pack_book() {   # pack_book <book_dir>
    local book_dir="$1"
    local book_id out_zip ts_file reason f tmp_zip latest_ts
    book_id="$(basename "$book_dir")"
    out_zip="$DIST_DIR/${book_id}.zip"
    ts_file="$book_dir/.timestamp"

    # 實際會進 zip 的內容；git 比對也只看這些路徑
    local -a payload=(chapters)
    for f in book.yaml book.yml; do
        if [[ -f "$book_dir/$f" ]]; then payload+=("$f"); fi
    done

    if [[ -z "$(find "$book_dir/chapters" -type f -print -quit)" ]]; then
        echo "Skipping $book_id (chapters is empty)"
        skipped=$((skipped + 1))
        return 0
    fi

    if ! reason="$(needs_pack "$book_dir" "$out_zip" "$ts_file" "${payload[@]}")"; then
        echo "Skipping $book_id (up-to-date)"
        skipped=$((skipped + 1))
        return 0
    fi

    echo "Packing $book_id -> $out_zip ($reason)"

    # 先打包到暫存檔，成功後才原子替換，失敗時不會毀掉舊的 zip
    tmp_zip="$TMP_DIR/${book_id}.zip"
    rm -f "$tmp_zip"
    (
        cd "$book_dir"
        find "${payload[@]}" -type f \
            ! -name '.DS_Store' ! -name 'Thumbs.db' ! -name '*~' ! -name '*.swp' \
            -print | LC_ALL=C sort | zip -qX "$tmp_zip" -@
    )
    mv -f "$tmp_zip" "$out_zip"

    # 有未 commit 的修改或無 git 紀錄時記錄當下時間；否則記錄最新 commit 時間
    latest_ts="$(git_latest_ts "$book_dir" "${payload[@]}")"
    if git_dirty "$book_dir" "${payload[@]}" || [[ "$latest_ts" == 0 ]]; then
        date +%s > "$ts_file"
    else
        echo "$latest_ts" > "$ts_file"
    fi
    packed=$((packed + 1))
}

packed=0
skipped=0
for book_dir in "${BOOK_DIRS[@]}"; do
    pack_book "$book_dir"
done

echo "Done! (Packed $packed, skipped $skipped)"

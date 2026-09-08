#!/usr/bin/env bash
#
# Read one folder and print what the preview card needs, as tab-separated
# records on stdout. Never fails the caller: an unreadable or vanished folder
# prints an ERR record and exits 0, because a missing folder is a state the
# shelf draws, not an error it reports.
#
#   usage: bash scan.sh <path> <deep:0|1> <timeout-seconds> <thumbnails> <recents>
#
# Records:
#   STAT    <ls-style mode>|<owner>|<group>|<mtime epoch>
#   TOP     <files>  <dirs>                  entries directly in the folder
#   RECENT  <mtime>  <type>  <size>  <name>  most recently changed entries
#   DEEP    <files>  <dirs>  <bytes>         totals for the walk that was run
#   CAT     <key>    <count> <bytes>         one per file category present
#   THUMB   <path>                           an image to draw in the preview
#   PARTIAL 1                                the walk hit the timeout
#   ERR     <reason>

set -u

path=${1:-}
deep=${2:-1}
timeout_s=${3:-12}
thumbs=${4:-4}
recents=${5:-6}

[ -n "$path" ] || { printf 'ERR\tno-path\n'; exit 0; }
[ -d "$path" ] || { printf 'ERR\tmissing\n'; exit 0; }

stat_line=$(stat -c '%A|%U|%G|%Y' "$path" 2>/dev/null) || stat_line=""
[ -n "$stat_line" ] && printf 'STAT\t%s\n' "$stat_line"

[ -r "$path" ] && [ -x "$path" ] || { printf 'ERR\tunreadable\n'; exit 0; }

# Everything directly inside, counted by type.
find "$path" -mindepth 1 -maxdepth 1 -printf '%y\n' 2>/dev/null |
  awk '{ if ($1 == "d") d++; else f++ } END { printf "TOP\t%d\t%d\n", f + 0, d + 0 }'

# The most recently changed entries, newest first.
if [ "$recents" -gt 0 ]; then
  find "$path" -mindepth 1 -maxdepth 1 -printf '%T@\t%y\t%s\t%f\n' 2>/dev/null |
    sort -rn | head -n "$recents" | awk '{ print "RECENT\t" $0 }'
fi

# The walk. `%p` is only read to classify the name and to pick thumbnails —
# awk aggregates, so a tree with a hundred thousand files still answers with a
# couple of dozen lines. A timeout leaves the totals partial rather than
# absent, and says so, which is more use than a blank card.
read -r -d '' AWK_CLASSIFY <<'AWKPROG'
$1 == "PARTIAL" && NF == 1 { partial = 1; next }
{
  if ($1 == "d") { dirs++; next }
  files++
  bytes += $2
  name = $3
  sub(/.*\//, "", name)
  cat = "other"
  if (name ~ /\./) {
    ext = tolower(name)
    sub(/.*\./, "", ext)
    if (ext ~ /^(jpg|jpeg|png|gif|webp|bmp|svg|avif|heic|heif|tif|tiff|ico)$/) cat = "image"
    else if (ext ~ /^(mp4|mkv|avi|mov|webm|m4v|wmv|flv|mpg|mpeg)$/) cat = "video"
    else if (ext ~ /^(mp3|flac|wav|ogg|oga|m4a|opus|aac|wma)$/) cat = "audio"
    else if (ext ~ /^(pdf|doc|docx|odt|ods|odp|txt|md|rst|rtf|xls|xlsx|ppt|pptx|epub|mobi|djvu|csv)$/) cat = "doc"
    else if (ext ~ /^(js|jsx|ts|tsx|py|rb|go|rs|c|h|hpp|cc|cpp|java|kt|swift|sh|bash|zsh|fish|qml|json|yml|yaml|toml|ini|conf|html|css|scss|xml|lua|php|sql|vim|el|nix)$/) cat = "code"
    else if (ext ~ /^(zip|tar|gz|tgz|xz|bz2|7z|rar|zst|iso|img|deb|rpm|pkg)$/) cat = "archive"
  }
  count[cat]++
  size[cat] += $2
  if (cat == "image" && shown < want) { shown++; print "THUMB\t" $3 }
}
END {
  if (partial) print "PARTIAL\t1"
  printf "DEEP\t%d\t%d\t%.0f\n", files + 0, dirs + 0, bytes + 0
  for (c in count) printf "CAT\t%s\t%d\t%.0f\n", c, count[c], size[c]
}
AWKPROG

if [ "$deep" = "1" ]; then
  {
    timeout "$timeout_s" find "$path" -mindepth 1 \( -type f -o -type d \) \
      -printf '%y\t%s\t%p\n' 2>/dev/null
    # A killed `find` leaves its last line unterminated, so the marker opens
    # with a newline of its own or it lands glued to a truncated record.
    [ "$?" = "124" ] && printf '\nPARTIAL\n'
  } | awk -F'\t' -v want="$thumbs" "$AWK_CLASSIFY"
else
  find "$path" -mindepth 1 -maxdepth 1 \( -type f -o -type d \) \
    -printf '%y\t%s\t%p\n' 2>/dev/null |
    awk -F'\t' -v want="$thumbs" "$AWK_CLASSIFY"
fi

exit 0

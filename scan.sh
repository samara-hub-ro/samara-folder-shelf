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
#
# Everything `find` emits is NUL-terminated and read by awk with RS="\0",
# and every name is stripped of control characters before it is printed.
# A file name may contain a newline, and with newline-delimited records that
# is an injection: a file called $'x\nSTAT\tdrwxrwxrwx|root|root|0' forges a
# record, and the shelf shows somebody else's numbers — a wrong size, a wrong
# owner, a folder claimed to be world-writable when it is not. Nothing here
# reaches a shell, so this was never code execution; it was the card lying
# about the folder, on the say-so of whoever could drop a file into it.
#
# THUMB is the one record that cannot be sanitised, because the path has to
# stay usable as a path. Those are dropped instead: a picture whose name
# carries a newline goes unshown, which costs one thumbnail.

set -u

path=${1:-}
deep=${2:-1}
timeout_s=${3:-12}
thumbs=${4:-4}
recents=${5:-6}

[ -n "$path" ] || { printf 'ERR\tno-path\n'; exit 0; }
if [ ! -d "$path" ]; then
  if [ -e "$path" ]; then printf 'ERR\tnotdir\n'; else printf 'ERR\tmissing\n'; fi
  exit 0
fi

stat_line=$(stat -c '%A|%U|%G|%Y' "$path" 2>/dev/null) || stat_line=""
[ -n "$stat_line" ] && printf 'STAT\t%s\n' "$stat_line"

[ -r "$path" ] && [ -x "$path" ] || { printf 'ERR\tunreadable\n'; exit 0; }

# -H follows the starting point and nothing below it: a favourite that is a
# symlink to a real folder is the folder it points at, while a tree full of
# links back to / is still just a tree full of links.

# Everything directly inside, counted by type. Names are not read here, so
# there is nothing to forge.
find -H "$path" -mindepth 1 -maxdepth 1 -printf '%y\n' 2>/dev/null |
  awk '{ if ($1 == "d") d++; else f++ } END { printf "TOP\t%d\t%d\n", f + 0, d + 0 }'

# The most recently changed entries, newest first.
if [ "$recents" -gt 0 ]; then
  find -H "$path" -mindepth 1 -maxdepth 1 -printf '%T@\t%y\t%s\t%f\0' 2>/dev/null |
    sort -z -rn | head -z -n "$recents" |
    awk 'BEGIN { RS = "\0"; FS = "\t" }
         NF >= 4 {
           name = $4
           for (i = 5; i <= NF; i++) name = name "\t" $i
           gsub(/[[:cntrl:]]/, " ", name)
           printf "RECENT\t%s\t%s\t%s\t%s\n", $1, $2, $3, name
         }'
fi

# The walk. `%p` is only read to classify the name and to pick thumbnails —
# awk aggregates, so a tree with a hundred thousand files still answers with a
# couple of dozen lines. A timeout leaves the totals partial rather than
# absent, and says so, which is more use than a blank card.
read -r -d '' AWK_CLASSIFY <<'AWKPROG'
BEGIN { RS = "\0"; FS = "\t" }
$0 == "PARTIAL" && NF == 1 { partial = 1; next }
NF >= 3 {
  path = $3
  for (i = 4; i <= NF; i++) path = path "\t" $i
  if ($1 == "d") { dirs++; next }
  files++
  bytes += $2
  name = path
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
  # A path with a control character in it cannot be written on a line and
  # still be opened from one, so it is simply not offered as a thumbnail.
  if (cat == "image" && shown < want && path !~ /[[:cntrl:]]/) {
    shown++
    printf "THUMB\t%s\n", path
  }
}
END {
  if (partial) print "PARTIAL\t1"
  printf "DEEP\t%d\t%d\t%.0f\n", files + 0, dirs + 0, bytes + 0
  for (c in count) printf "CAT\t%s\t%d\t%.0f\n", c, count[c], size[c]
}
AWKPROG

if [ "$deep" = "1" ]; then
  {
    timeout "$timeout_s" find -H "$path" -mindepth 1 \( -type f -o -type d \) \
      -printf '%y\t%s\t%p\0' 2>/dev/null
    # A killed `find` leaves its last record unterminated, so the marker opens
    # with a NUL of its own or it lands glued to that truncated record.
    [ "$?" = "124" ] && printf '\0PARTIAL'
  } | awk -v want="$thumbs" "$AWK_CLASSIFY"
else
  find -H "$path" -mindepth 1 -maxdepth 1 \( -type f -o -type d \) \
    -printf '%y\t%s\t%p\0' 2>/dev/null |
    awk -v want="$thumbs" "$AWK_CLASSIFY"
fi

exit 0

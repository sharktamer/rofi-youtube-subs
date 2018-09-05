#!/usr/bin/env sh

TAB=$'\t'

# defaults
BROWSER=${BROWSER:-chromium}
PLAYER=${PLAYER:-mpv}
CACHE_DIR=${XDG_CACHE_DIR:-~/.cache}/rofi-youtube-subs
REFRESH=false
EXIT=false
STALE=false

usage() {
    echo "$0 [-c CACHE_DIR] [-r] [-x] [-s] [-p PLAYER] [-b BROWSER] [-t SIZE]"
    echo "  -c CACHE_DIR    directory to store subscriptions cache"
    echo "  -r              refresh subscriptions"
    echo "  -x              exit before showing rofi (only makes sense with -r)"
    echo "  -s SECONDS      time in seconds before cache becomes stale"
    echo "  -p PLAYER       video player to use"
    echo "  -b BROWSER      browser to use"
    echo "  -t FONT_SIZE    font size used by rofi"
    echo "  -h "
}

while getopts 'c:rxs:p:b:t:h' opt; do
  case "$opt" in
    c)
      CACHE_DIR="${OPTARG}"
      ;;
    r)
      REFRESH=true
      ;;
    x)
      EXIT=true
      ;;
    s)
      # Compare the time x seconds ago to the mtime of the cache file
      CACHE_AGE=$(stat -c %Y "${CACHE_DIR}/subs.tsv")
      CUTOFF=$(( $(date +%s) - ${OPTARG} ))
      [[ ${CACHE_AGE} < ${CUTOFF} ]] && STALE=true
      ;;
    p)
      PLAYER="${OPTARG}"
      ;;
    b)
      BROWSER="${OPTARG}"
      ;;
    t)
      FONT="Sans ${OPTARG}"
      ;;
    h)
      usage
      exit
      ;;
    ?)
      usage
      exit 1
      ;;
  esac
done
shift $(( OPTIND - 1 ))

# If cache does not exist, cache is stale, or refresh is forced
( [ ! -f "${CACHE_DIR}/subs.tsv" ] || $STALE || $REFRESH ) && {
    # check if the youtube-viewer command is available
    command -v youtube-viewer >/dev/null || {
        echo "youtube-viewer is needed for caching" >&2
        exit 1
    }

    mkdir -p ${CACHE_DIR}

    # run youtube-viewer, extracting info for 50 newest subs and output to cache
    youtube-viewer -SV --results=50 --no-interactive\
        --extract="*AUTHOR*${TAB}*TITLE*${TAB}*URL*" --std-in=1..50\
        --really-quiet --extract-file=${CACHE_DIR}/subs.tsv

    # delete first line from cache containing just the date
    sed -i '1d' "${CACHE_DIR}/subs.tsv"
}

# If -x flag is passed, exit at this point
$EXIT && exit

# Use readarray builtin to read lines of file into array
readarray -t subs < ~/.cache/rofi-youtube-subs/subs.tsv

# Run rofi on author and description, storing the index of the chosen line
sub_index=$(
    for sub in "${subs[@]}";{
        # extract fields from line, separating on tab
        IFS=${TAB} read author desc link <<< ${sub}
        echo "${author}: ${desc}"
    }|rofi -no-show-icons -p "Subscriptions: " -i -dmenu -format i\
        -kb-custom-1 alt+Return -kb-custom-2 alt+r
)
# Keep the exit status of rofi, which can be used to determine the pressed key
exit_status=$?

# store line selected from rofi
sub="${subs[${sub_index}]}"
# extract the final field, the url
sub_url="${sub##*${TAB}}"

case $exit_status in
    # if escape was pressed
    1)
      exit
      ;;
    # if enter was pressed
    0)
      # open url in video player
      ${PLAYER} "${sub_url}"
      ;;
    # if alt+enter was pressed
    10)
      # open url in browser
      ${BROWSER} "${sub_url}"
      ;;
    # if alt+r was pressed
    11)
      # run refresh operation and open rofi again
      $0 -r
esac

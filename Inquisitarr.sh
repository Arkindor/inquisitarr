#!/bin/bash
set -u -o pipefail

API_URL="http://YOUR-SERVER_IP:5055/api/v1"
API_KEY="YOUR_SEER_API_KEY"
MAX_PARALLEL=10

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

die() { echo "Error: $*" >&2; exit 1; }
count_lines() { [[ -f "$1" ]] && wc -l < "$1" || echo 0; }

for cmd in curl jq xargs; do
    command -v "$cmd" >/dev/null 2>&1 || die "$cmd is not installed"
done

read -r -p "Keyword to search: " KEYWORD
[[ -n "${KEYWORD// }" ]] || die "empty keyword"

read -r -p "Max number of movies to blacklist (0=all): " MAX_MOVIES
MAX_MOVIES=${MAX_MOVIES:-0}
[[ "$MAX_MOVIES" =~ ^[0-9]+$ ]] || die "invalid number"

echo -n "Searching keyword '$KEYWORD'... "
KEYWORD_ID=$(curl -sS --get \
    -H "X-Api-Key: $API_KEY" \
    --data-urlencode "query=$KEYWORD" \
    "$API_URL/search/keyword" | jq -r '.results[0].id // empty') || die "failed"
[[ -n "$KEYWORD_ID" ]] || die "keyword not found"
echo "OK (ID=$KEYWORD_ID)"

MOVIES_INFO=$(curl -sS -H "X-Api-Key: $API_KEY" \
    "$API_URL/discover/keyword/$KEYWORD_ID/movies") || die "failed to fetch movies"

TOTAL_RESULTS=$(jq -r '.totalResults // 0' <<< "$MOVIES_INFO")
TOTAL_PAGES=$(jq -r '.totalPages // 0' <<< "$MOVIES_INFO")
PER_PAGE=$(jq -r '.results | length' <<< "$MOVIES_INFO")
(( PER_PAGE > 0 )) || PER_PAGE=20

(( TOTAL_RESULTS == 0 )) && { echo "No movies found."; exit 0; }

if (( MAX_MOVIES == 0 || MAX_MOVIES > TOTAL_RESULTS )); then
    MAX_MOVIES=$TOTAL_RESULTS
fi

PAGES_NEEDED=$(( (MAX_MOVIES + PER_PAGE - 1) / PER_PAGE ))
(( PAGES_NEEDED > TOTAL_PAGES )) && PAGES_NEEDED=$TOTAL_PAGES

echo "Available movies: $TOTAL_RESULTS | To process: $MAX_MOVIES"

# Collect movies (reuse first page)
MOVIES_FILE="$TMP_DIR/movies.b64"
jq -r '.results[]? | {id, title} | @base64' <<< "$MOVIES_INFO" > "$MOVIES_FILE"

for ((page=2; page<=PAGES_NEEDED; page++)); do
    curl -sS -H "X-Api-Key: $API_KEY" \
        "$API_URL/discover/keyword/$KEYWORD_ID/movies?page=$page" | \
        jq -r '.results[]? | {id, title} | @base64' >> "$MOVIES_FILE"
done

head -n "$MAX_MOVIES" "$MOVIES_FILE" > "$TMP_DIR/to_process.b64"
TOTAL_TO_PROCESS=$(count_lines "$TMP_DIR/to_process.b64")
(( TOTAL_TO_PROCESS == 0 )) && { echo "No movies to process."; exit 0; }

blacklist_movie() {
    local MOVIE_B64="$1"
    local TMP_DIR="$2"
    local MOVIE_JSON TMDB_ID TITLE PAYLOAD HTTP_CODE BODY BODY_FILE

    MOVIE_JSON=$(printf '%s' "$MOVIE_B64" | base64 -d 2>/dev/null) || {
        echo 1 >> "$TMP_DIR/fail"; return
    }

    TMDB_ID=$(jq -r '.id // empty' <<< "$MOVIE_JSON")
    TITLE=$(jq -r '.title // empty' <<< "$MOVIE_JSON")
    [[ -z "$TMDB_ID" || -z "$TITLE" ]] && { echo 1 >> "$TMP_DIR/fail"; return; }

    PAYLOAD=$(jq -cn \
        --arg tmdbId "$TMDB_ID" \
        --arg title "$TITLE" \
        '{tmdbId:($tmdbId|tonumber),title:$title,mediaType:"movie",user:1,media:{status:0}}')

    BODY_FILE="$TMP_DIR/resp_$$_${TMDB_ID}"

    HTTP_CODE=$(curl -sS -o "$BODY_FILE" -w "%{http_code}" \
        -X POST \
        -H "X-Api-Key: $API_KEY" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" \
        "$API_URL/blacklist") || {
            echo 1 >> "$TMP_DIR/fail"; rm -f "$BODY_FILE"; return
        }

    BODY=$(cat "$BODY_FILE" 2>/dev/null)
    rm -f "$BODY_FILE"

    case "$HTTP_CODE" in
        200|201|204)
            echo 1 >> "$TMP_DIR/ok"
            ;;
        409|412)
            echo 1 >> "$TMP_DIR/existing"
            ;;
        *)
            if grep -qi "already\|blocklist\|blacklist" <<< "$BODY"; then
                echo 1 >> "$TMP_DIR/existing"
            else
                echo 1 >> "$TMP_DIR/fail"
                echo "HTTP $HTTP_CODE | $TMDB_ID | $TITLE" >&2
            fi
            ;;
    esac
}

export -f blacklist_movie
export API_URL API_KEY

echo "Blacklisting in progress... ($MAX_PARALLEL parallel requests)"

tr '\n' '\0' < "$TMP_DIR/to_process.b64" | \
    xargs -0 -r -n 1 -P "$MAX_PARALLEL" bash -c 'blacklist_movie "$2" "$1"' _ "$TMP_DIR"

ADDED=$(count_lines "$TMP_DIR/ok")
EXISTING=$(count_lines "$TMP_DIR/existing")
FAILED=$(count_lines "$TMP_DIR/fail")
PROCESSED=$((ADDED + EXISTING + FAILED))

echo "Result: $ADDED added | $EXISTING already listed | $FAILED failed | $PROCESSED/$TOTAL_TO_PROCESS processed"

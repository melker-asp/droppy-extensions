#!/bin/zsh
# Hands the selection to the Todoist droplet in Droppy through
# droppy://droplet/todoist/add. The droplet holds the API token and talks to
# Todoist; this script only builds the link.
#
# $1: edit (open the shelf with the text in the quick add field),
#     today or tomorrow (add straight away with that date).

mode=${1:-edit}
text=${DROPCLIP_TEXT:-$OPENCLIP_TEXT}
bundle=${DROPCLIP_BUNDLE_ID:-$OPENCLIP_BUNDLE_ID}

# One line, no runs of whitespace. A long selection keeps its first 300
# characters as the task and goes whole into the description.
content=$(print -r -- "$text" | tr '\r\n\t' '   ' | tr -s ' ')
content=${content## }
content=${content%% }
[[ -z $content ]] && exit 0
note=""
if (( ${#content} > 300 )); then
  note=$text
  content="${content[1,300]}…"
fi

# A link back to where the text was selected: the browser tab or the mail.
# Needs Automation access for Droppy the first time; without it there is
# simply no link.
source_link=""
case $bundle in
  ai.perplexity.comet|com.google.Chrome|com.brave.Browser|com.microsoft.edgemac|company.thebrowser.Browser|com.vivaldi.Vivaldi)
    source_link=$(osascript -e "tell application id \"$bundle\" to get URL of active tab of front window" 2>/dev/null) ;;
  com.apple.Safari)
    source_link=$(osascript -e 'tell application id "com.apple.Safari" to get URL of front document' 2>/dev/null) ;;
  com.apple.mail)
    mid=$(osascript -e 'tell application "Mail" to get message id of item 1 of (get selection)' 2>/dev/null)
    [[ -n $mid ]] && source_link="message://%3C${mid}%3E" ;;
esac
if [[ $source_link == http* || $source_link == message:* ]]; then
  note=${note:+$note$'\n\n'}$source_link
fi

encode() { osascript -l JavaScript -e 'function run(argv) { return encodeURIComponent(argv[0]) }' -- "$1"; }

url="droppy://droplet/todoist/add?text=$(encode "$content")"
[[ -n $note ]] && url+="&note=$(encode "$note")"
case $mode in
  today)    url+="&mode=plain&due=today" ;;
  tomorrow) url+="&mode=plain&due=tomorrow" ;;
  *)        url+="&mode=edit" ;;
esac

open "$url"

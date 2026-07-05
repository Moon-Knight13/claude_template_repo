# Compute the desired, ordered single-select option set for updateProjectV2Field.
#
# Inputs (via --argjson):
#   $existing : array of {id,name,color,description} as returned by the API (may be []).
#   $wanted   : array of desired option-name strings, in canonical order.
#
# Output: ordered array of {id?,name,color,description}. Wanted names come first in
# $wanted order, each reusing the FIRST existing option with that name (so its id,
# color and description — and therefore its cards — are preserved). Every remaining
# existing option is then appended, matched BY ID so duplicate-named options are
# never collapsed or dropped. Colors: existing kept; new options get a cycling
# default. This is the single source of truth for option order.
def colors: ["GRAY","BLUE","GREEN","YELLOW","ORANGE","RED","PURPLE","PINK"];

([ $wanted[] as $w | ([ $existing[] | select(.name == $w) ][0]) // {name: $w} ]) as $wantedOpts
| ([ $wantedOpts[] | .id ] | map(select(. != null))) as $usedIds
| ([ $existing[] | select((.id // null) as $i | ($i == null) or (($usedIds | index($i)) | not)) ]) as $extras
| ($wantedOpts + $extras)
| to_entries
| map(
    .key as $i
    | .value
    | {
        name: .name,
        color: (.color // colors[$i % (colors | length)]),
        description: (.description // "")
      }
      + (if .id then { id: .id } else {} end)
  )

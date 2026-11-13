# drop-deleted.jq: the fixture without the items the run already deleted ($d: their ids or names).
def live: map(select(((.id // "" | tostring) as $i | $d | index($i) | not) and ((.name // "") as $n | $d | index($n) | not)));
if type == "array" then live
else with_entries(if (.value | type) == "array" then .value |= live else . end)
end

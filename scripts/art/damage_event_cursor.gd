## Presentation consumer for retained, monotonically sequenced events.
## Never mutates StageRuntime; exposes missed events instead of hiding truncation.
class_name DamageEventCursor
extends RefCounted

var last_sequence: int = 0
var missed_events: int = 0

func consume(events: Array[Dictionary]) -> Array[Dictionary]:
	var fresh: Array[Dictionary] = []
	for event: Dictionary in events:
		var seq := int(event.get("seq", 0))
		if seq <= last_sequence:
			continue
		missed_events += maxi(0, seq - last_sequence - 1)
		last_sequence = seq
		fresh.append(event)
	return fresh

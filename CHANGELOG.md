## 0.2.0

* Align with backend camelCase migration: SDK now sends and receives camelCase JSON keys natively (removed snake_case ↔ camelCase transforms on request bodies and responses).
* Renamed query params `mark_seen`/`mark_read` → `markSeen`/`markRead` and `target_type`/`target_id` → `targetType`/`targetId`.
* Removed legacy `option_id` fallback in poll user-vote parsing.

## 0.1.0

* Initial release.

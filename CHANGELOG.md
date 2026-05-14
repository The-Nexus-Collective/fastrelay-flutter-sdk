## 0.3.0

* Support aggregated notification feeds in `FastRelayFeed.getNotificationActivities()`. `NotificationPage` now exposes a typed `groups: List<NotificationGroup<T>>` (with `groupKey`, `activities`, `activityCount`, `createdAt`, `updatedAt`) when the server returns an aggregated response, and also flattens group activities into `data` so existing consumers keep working. Previously aggregated payloads silently parsed as zero activities.
* `NotificationPage.fromJson` now throws `StateError` if a response is missing both `data` and `groups` (server contract violation) instead of returning an empty page.

## 0.2.0

* Align with backend camelCase migration: SDK now sends and receives camelCase JSON keys natively (removed snake_case ↔ camelCase transforms on request bodies and responses).
* Renamed query params `mark_seen`/`mark_read` → `markSeen`/`markRead` and `target_type`/`target_id` → `targetType`/`targetId`.
* Removed legacy `option_id` fallback in poll user-vote parsing.

## 0.1.0

* Initial release.

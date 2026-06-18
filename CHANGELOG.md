## 0.4.1

* `FastRelayActivity` now exposes `ownReactions: List<FastRelayReaction>?` — the reactions the requesting user made, embedded directly in feed and single-activity responses. `null` when not enriched (server-side auth), empty list when the user has none. Lets consumers drop the per-activity `listReactions` fan-out on feed load (`1 + N + M` → `1 + N` round-trips).

## 0.4.0

* Add video upload support. New `FastRelayClient.videos` API (`createUploadUrl`, `get`, `delete`) mints tus upload URLs against `/v1/videos`, and the top-level `uploadVideoBytes()` / `tusUploadBytes()` helpers drive a resumable tus 1.0.0 upload directly to Cloudflare Stream with chunked PATCHes and optional progress callbacks.
* Add `FastRelayVideo`, `FastRelayVideoUploadUrl`, and `FastRelayVideoStatusEvent` models, plus `FastRelayVideoUploadProgress`, `FastRelayVideoUploadResult`, and `FastRelayVideoUploadException`.
* `FastRelayRealtime` now exposes `videoStatusEvents` for `video.ready` / `video.failed` server events so callers can react to processing completion without polling `getVideo`.

## 0.3.0

* Support aggregated notification feeds in `FastRelayFeed.getNotificationActivities()`. `NotificationPage` now exposes a typed `groups: List<NotificationGroup<T>>` (with `groupKey`, `activities`, `activityCount`, `createdAt`, `updatedAt`) when the server returns an aggregated response, and also flattens group activities into `data` so existing consumers keep working. Previously aggregated payloads silently parsed as zero activities.
* `NotificationPage.fromJson` now throws `StateError` if a response is missing both `data` and `groups` (server contract violation) instead of returning an empty page.

## 0.2.0

* Align with backend camelCase migration: SDK now sends and receives camelCase JSON keys natively (removed snake_case ↔ camelCase transforms on request bodies and responses).
* Renamed query params `mark_seen`/`mark_read` → `markSeen`/`markRead` and `target_type`/`target_id` → `targetType`/`targetId`.
* Removed legacy `option_id` fallback in poll user-vote parsing.

## 0.1.0

* Initial release.

# fastrelay Feed Flutter SDK

Flutter SDK for [fastrelay](https://fastrelay.io) activity feeds — feeds, activities, reactions, comments, polls, video uploads, moderation, and realtime updates over WebSocket.

- Feed-first API: `fastrelay.feed(group, id)`
- User (JWT) and server (API key + secret) auth
- Idiomatic Dart `camelCase` payloads
- Realtime subscriptions with automatic reconnect + token refresh
- Polling fallback for non-realtime environments
- Direct-to-storage video uploads (tus / Cloudflare Stream)
- Structured `fastrelayApiError` with rate-limit metadata

## Contents

- [Requirements](#requirements)
- [Install](#install)
- [Quick start](#quick-start)
- [Authentication](#authentication)
- [Feeds](#feeds)
- [Activities, reactions, comments](#activities-reactions-comments)
- [Realtime](#realtime)
- [Polling fallback](#polling-fallback)
- [Video upload](#video-upload)
- [Aggregated / notification feeds](#aggregated--notification-feeds)
- [Error handling](#error-handling)
- [Links](#links)

## Requirements

- Dart SDK `^3.10.0`
- Flutter `>=1.17.0`

## Install

Add the package to `pubspec.yaml`:

```yaml
dependencies:
  fastrelay_feed_sdk:
    git:
      url: https://github.com/The-Nexus-Collective/fastrelay-flutter-sdk
      ref: v0.4.0
```

Then:

```bash
flutter pub get
```

## Quick start

```dart
import 'package:fastrelay_feed_sdk/fastrelay_feed_sdk.dart';

final fastrelay = fastrelayClient(
  apiKey: 'your_api_key',
  baseUrl: 'https://api.fastrelay.io',
);

await fastrelay.connectUser(
  {'id': 'john', 'displayName': 'John Doe'},
  'user_jwt_token',
);

final timeline = fastrelay.feed('timeline', 'john');
await timeline.getOrCreate();

await timeline.addActivity({
  'type': 'post',
  'text': 'Hello fastrelay!',
});

final page = await timeline.getActivities(query: {'limit': 25});
```

All request and response payloads are plain `Map<String, dynamic>` in `camelCase`. Typed models (`fastrelayActivity`, `fastrelayReaction`, `fastrelayComment`, `CursorPage<T>`, etc.) are returned by the strongly-typed helpers on `fastrelayClient` — see [Activities, reactions, comments](#activities-reactions-comments).

## Authentication

### User auth (mobile / client apps)

Mint a short-lived JWT on your backend and pass it to `connectUser`:

```dart
await fastrelay.connectUser(
  {
    'id': 'john',
    'displayName': 'John Doe',
    // optional fields
    'profileData': {'avatarUrl': 'https://...'},
    'role': 'user',
  },
  'user_jwt_token',
  upsertUser: true, // create or update the user on fastrelay
  realtime: true,   // also open the websocket
  tokenProvider: () async => fetchFreshJwtFromBackend(),
);
```

`tokenProvider` is called transparently when the realtime channel receives a `4003 TOKEN_EXPIRED` close — no manual reconnect needed.

### Server auth (backend / scripts)

```dart
final fastrelay = fastrelayClient(
  apiKey: 'your_api_key',
  apiSecret: 'your_api_secret',
  baseUrl: 'https://api.fastrelay.io',
);

final token = await fastrelay.tokens.issue({
  'userId': 'john',
  'role': 'user',
  'expiresIn': 3600,
});
```

Server-only endpoints (token issuance, moderation admin, bans, blocklists, …) require `apiSecret` and are gated by `fastrelayAuthMode.server`.

## Feeds

```dart
final feed = fastrelay.feed('timeline', 'john');

await feed.getOrCreate();
await feed.getActivities(query: {'limit': 25, 'view': 'trending'});
await feed.getCapabilities();

await feed.addActivity({'type': 'post', 'text': 'hello'});
await feed.follow('user:jane');
await feed.batchFollow(['user:jane', 'user:bob']);
await feed.unfollow('user:jane', keepHistory: false);

await feed.setVisibility('public');
await feed.updateSettings({'followApproval': 'required'});
await feed.addMember('user_jane', role: 'moderator');
await feed.listMembers(query: {'limit': 25});
await feed.removeMember('user_jane');
await feed.delete();
```

## Activities, reactions, comments

The strongly-typed helpers return models from `lib/src/models/` and `CursorPage<T>` for paginated lists:

```dart
final reaction = await fastrelay.addReaction('act_123', type: 'like');
await fastrelay.removeReaction('act_123', reaction.id);

final comments = await fastrelay.listComments('act_123', limit: 25);
for (final comment in comments.items) {
  // `user` is the embedded author object (null when not enriched)
  print('${comment.user?.displayName ?? comment.userId}: ${comment.text}');
}

await fastrelay.addBookmark('act_123');

final poll = await fastrelay.createPoll(
  'act_123',
  question: 'Pick one',
  choices: [
    {'id': 'a', 'text': 'Option A'},
    {'id': 'b', 'text': 'Option B'},
  ],
);
await fastrelay.vote(poll.id, optionId: 'a');
```

## Realtime

Pass `realtime: true` to `connectUser`, then listen on the streams exposed by `fastrelay.realtime`:

```dart
final realtime = fastrelay.realtime!;

realtime.connectionStateStream.listen((state) {
  print('connection: $state'); // connecting, connected, reconnecting, disconnected
});

realtime.errors.listen((error) {
  print('realtime error: ${error.code} ${error.message}');
});

final timelineEvents = realtime.eventsForFeed('timeline:john');
final activityAdds = realtime.eventsForFeed('timeline:john', type: 'activity.added');

final sub = timelineEvents.listen((event) {
  print('${event.type} on ${event.feedId}: ${event.payload}');
});

// Later:
await sub.cancel();
```

Subscriptions are reference-counted: subscribing to a feed stream sends a `subscribe` frame, and cancelling the last listener for a feed sends an `unsubscribe`. Reconnects automatically resubscribe and catch up missed activities.

By default, the connection suspends on `AppLifecycleState.paused` and resumes on `resumed`. Pass `maintainBackgroundConnection: true` to `connectUser` to keep it open in the background.

## Polling fallback

For environments where WebSocket is unavailable or undesired:

```dart
final polling = FeedPollingService(
  client: fastrelay,
  activeInterval: const Duration(seconds: 15),
  backgroundInterval: const Duration(seconds: 60),
);

polling.pollFeed('timeline', 'john', limit: 25).listen((page) {
  for (final activity in page.items) {
    print(activity.id);
  }
});

polling.pause();  // when app backgrounds
polling.resume(); // when app foregrounds
```

## Video upload

`uploadVideoBytes` mints a tus upload URL via the backend and PATCHes the bytes directly to Cloudflare Stream. The final `ready` state is signalled either via realtime (`video.ready` event on `realtime.videoStatusEvents`) or by polling `fastrelay.getVideo(videoId)`.

```dart
final result = await uploadVideoBytes(
  fastrelay,
  bytes: await file.readAsBytes(),
  filename: 'clip.mp4',
  mimeType: 'video/mp4',
  onProgress: (p) => print('${(p.fraction * 100).toStringAsFixed(1)}%'),
);

fastrelay.realtime?.videoStatusEvents
    .where((event) => event.videoId == result.videoId)
    .listen((event) => print('video ${event.videoId}: ${event.status}'));
```

## Aggregated / notification feeds

For feeds configured with aggregation (notifications, grouped activity), use `getNotificationFeedActivities`, which returns `NotificationPage<fastrelayActivity>` with grouped entries and unseen/unread counts:

```dart
final notifications = await fastrelay.getNotificationFeedActivities(
  'notification',
  'john',
  query: {'limit': 25},
);

print('unseen: ${notifications.unseen}, unread: ${notifications.unread}');
for (final group in notifications.groups) {
  print('${group.group}: ${group.activityCount} activities');
}
```

## Error handling

Every non-2xx response throws `fastrelayApiError` with the parsed error envelope plus rate-limit headers:

```dart
try {
  await fastrelay.activities.get('act_missing');
} on fastrelayApiError catch (error) {
  print('${error.status} ${error.code}: ${error.message}');
  print('hint: ${error.hint}');
  print('requestId: ${error.requestId}');
  print('rateLimit: ${error.rateLimit?.remaining}/${error.rateLimit?.limit}');
}
```

## Links

- Repository: <https://github.com/The-Nexus-Collective/fastrelay-flutter-sdk>
- Changelog: [CHANGELOG.md](CHANGELOG.md)
- Issues: <https://github.com/The-Nexus-Collective/fastrelay-flutter-sdk/issues>

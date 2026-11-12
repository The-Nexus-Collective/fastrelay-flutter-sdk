# fastrelay Feed Flutter SDK

Flutter SDK for [fastrelay](https://fastrelay.io) activity feeds and chat — feeds, activities, reactions, comments, polls, video uploads, moderation, direct and group chat, and realtime updates over WebSocket.

- Feed-first API: `fastrelay.feed(group, id)`
- Client-only by design: user (JWT) auth, no server secrets in the app
- Idiomatic Dart `camelCase` payloads
- Realtime subscriptions with automatic reconnect + token refresh
- Chat: direct/group conversations, messages, read receipts, typing, presence and reconnect sync on the same user, token and socket
- Polling fallback for non-realtime environments
- Direct-to-storage image uploads (presigned PUT) and video uploads (tus / Cloudflare Stream)
- Structured `FastrelayApiError` with rate-limit metadata

## Contents

- [Requirements](#requirements)
- [Install](#install)
- [Quick start](#quick-start)
- [Authentication](#authentication)
- [Feeds](#feeds)
- [Activities, reactions, comments](#activities-reactions-comments)
- [Realtime](#realtime)
- [Chat](#chat)
- [Polling fallback](#polling-fallback)
- [File upload](#file-upload)
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
      ref: v1.1.0
```

Then:

```bash
flutter pub get
```

## Quick start

```dart
import 'package:fastrelay_feed_sdk/fastrelay_feed_sdk.dart';

final fastrelay = FastrelayClient(
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

All request and response payloads are plain `Map<String, dynamic>` in `camelCase`. Typed models (`FastrelayActivity`, `FastrelayReaction`, `FastrelayComment`, `CursorPage<T>`, etc.) are returned by the strongly-typed helpers on `FastrelayClient` — see [Activities, reactions, comments](#activities-reactions-comments).

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
  realtime: true, // also open the websocket
  tokenProvider: () async => fetchFreshJwtFromBackend(),
);
```

`tokenProvider` is called transparently when a REST request gets a `401`, when the realtime channel closes with `4003 TOKEN_EXPIRED` or rejects the handshake with `4002`, and before reconnecting with an expired token. No manual reconnect is needed.

### Client-only by design

This SDK covers the client-side API only and authenticates with a user JWT.
Server-to-server operations — issuing tokens (`POST /v1/tokens`), managing
other users, feed groups, and moderation administration (bans, blocklists,
regex filters, flag review, content checks) — require the API secret and must
be called from your backend, never from an app. Your backend issues the user
JWT and hands it to `connectUser`; `upsertUser: true` then creates or updates
the connecting user's own record with that JWT.

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
for (final comment in comments.data) {
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
final activityAdds = realtime.eventsForFeed('timeline:john', type: 'activity.created');

final sub = timelineEvents.listen((event) {
  print('${event.type} on ${event.feedId}: ${event.data}');
});

// Later:
await sub.cancel();
```

Subscriptions are reference-counted: subscribing to a feed stream sends a `subscribe` frame, and cancelling the last listener for a feed sends an `unsubscribe`. Reconnects automatically resubscribe, but events sent while the socket was down are not replayed. Every (re)connect emits on `connectionEstablished`; when `isReconnect` is true, reload the feeds you are showing:

```dart
realtime.connectionEstablished
    .where((event) => event.isReconnect)
    .listen((_) => reloadVisibleFeeds());
```

By default, the connection suspends on `AppLifecycleState.paused` and resumes on `resumed`. Pass `maintainBackgroundConnection: true` to `connectUser` to keep it open in the background.

## Chat

Chat runs on the same user, JWT and realtime socket as feeds.

### Conversations and messages

```dart
// Direct conversations are idempotent: creating one that exists returns it.
final dm = await fastrelay.createConversation(kind: 'direct', members: ['jane']);

final team = await fastrelay.createConversation(
  type: 'messaging',
  members: ['jane', 'amy'],
  name: 'Launch',
  presenceEnabled: true,
);

final inbox = await fastrelay.queryConversations(
  filter: const FastrelayConversationFilter(hasUnread: true),
  sort: 'lastMessageAt',
  limit: 25,
);

final message = await fastrelay.sendMessage(
  team.id,
  text: 'Ship it?',
  replyToId: previous.id, // optional quote-reply
  options: const FastrelayRequestOptions(idempotencyKey: 'local-id-123'),
);

// Messages come back in ascending `seq`. Page backwards with `nextCursor`.
final latest = await fastrelay.listMessages(team.id, limit: 50);
final older = await fastrelay.listMessages(team.id, cursor: latest.nextCursor);
final aroundJump = await fastrelay.listMessages(team.id, around: 120, limit: 30);

await fastrelay.updateMessage(message.id, text: 'Ship it!');
await fastrelay.deleteMessage(message.id);

// Reactions return the updated message. `reactions` holds the first 100 users
// per type and `reactionCounts` the totals; page the rest.
final reacted = await fastrelay.addMessageReaction(message.id, '❤️');
await fastrelay.removeMessageReaction(message.id, '❤️');
final reactors = await fastrelay.listMessageReactionUsers(message.id, '❤️', limit: 50);

// No push for you; messages still arrive and count as unread.
await fastrelay.muteConversation(team.id);
await fastrelay.unmuteConversation(team.id);

final totals = await fastrelay.markConversationRead(team.id); // or seq: N
final unread = await fastrelay.getUnreadTotals();
```

Members: `listConversationMembers`, `addConversationMembers`, `updateConversationMember` (role / `restriction: 'banned' | 'muted' | 'none'`) and `removeConversationMember` (pass your own id to leave). Conversations: `getConversation`, `updateConversation`, `truncateConversation`, `deleteConversation`. The same calls are grouped under `fastrelay.conversations`, `fastrelay.messages` and `fastrelay.chat`.

### Realtime chat events

Chat events arrive on `realtime.chatEvents` — never on the feed streams. Each event has `type`, `conversationId` (null for `presence.changed` and `unread.updated`), `eventId`, `createdAt`, the raw `data`, and typed accessors decoded with the REST models:

```dart
realtime.chatEvents.listen((event) {
  switch (event.type) {
    case FastrelayChatEventType.messageNew:
    case FastrelayChatEventType.messageUpdated:
    case FastrelayChatEventType.messageDeleted:
      upsertMessage(event.message!);
    case FastrelayChatEventType.conversationUpdated:
      upsertConversation(event.conversation!); // realtime omits `members`
    case FastrelayChatEventType.memberAdded:
      print('${event.userIds} joined ${event.conversationId}');
    case FastrelayChatEventType.receiptRead:
      print('${event.userId} read up to ${event.lastReadSeq}');
    case FastrelayChatEventType.typingStart:
      showTyping(event.conversationId!, event.userId!);
    case FastrelayChatEventType.presenceChanged:
      print('${event.userId} online=${event.online}');
    case FastrelayChatEventType.unreadUpdated:
      setBadge(event.totals!.totalUnread);
    default:
      print('unhandled ${event.type}: ${event.data}'); // forward compatible
  }
});
```

Also: `conversation.truncated`, `conversation.deleted`, `member.removed` (`userId`), `member.updated` (`member`), `receipt.delivered`, `typing.stop`.

### Typing, receipts and presence

These are fire-and-forget socket messages. They return `false` (and are not queued) while the socket is not connected — fall back to REST where it matters:

```dart
realtime.startTyping(conversationId);
realtime.stopTyping(conversationId);
realtime.markDelivered(conversationId, message.seq);
if (!realtime.markRead(conversationId, seq: message.seq)) {
  await fastrelay.markConversationRead(conversationId, seq: message.seq);
}

// Opt this connection into presence. Re-sent automatically after every
// reconnect; you go offline when the connection closes.
realtime.startPresence();
```

Server-side rejections (not a member, invalid seq, ...) arrive on `realtime.errors`. Debouncing typing and batching read receipts is left to the app.

### Catching up after a reconnect

Every successful (re)connect emits the server's `connection.established` on `realtime.connectionEstablished`. Keep its `serverTime` from the first connect as the sync anchor; after a reconnect, ask for everything that changed since and move the anchor forward:

```dart
DateTime? anchor;

realtime.connectionEstablished.listen((established) async {
  if (anchor == null || !established.isReconnect) {
    anchor = established.serverTime;
    return;
  }
  final sync = await fastrelay.syncChat(
    since: anchor!,
    conversationIds: localConversationIds,
  );
  anchor = sync.serverTime;
  if (sync.reloadAll) {
    // Too much changed: reload via queryConversations.
  }
  // Apply sync.conversations / sync.messages, drop sync.removedConversationIds,
  // reload history for sync.reloadConversationIds, show sync.unread.
});
```

### Blocking and flagging

Blocking reuses the mute API with `type: 'block'`; it hides the user's messages and suppresses typing and presence in both directions. Messages are flagged with the existing flag API:

```dart
await fastrelay.createMute('spammer', type: 'block');
await fastrelay.listMutes(type: 'block');
await fastrelay.removeMute('spammer', type: 'block');

await fastrelay.createFlag('message', message.id, reason: 'spam');
```

## Polling fallback

For environments where WebSocket is unavailable or undesired:

```dart
final polling = FeedPollingService(
  client: fastrelay,
  activeInterval: const Duration(seconds: 15),
  backgroundInterval: const Duration(seconds: 60),
);

polling.pollFeed('timeline', 'john', limit: 25).listen((page) {
  for (final activity in page.data) {
    print(activity.id);
  }
});

polling.pause();  // when app backgrounds
polling.resume(); // when app foregrounds
```

## File upload

`uploadFileDirect` sends an image or video straight to storage: it reserves the file, PUTs the bytes to a presigned URL and confirms the upload. The content type must be an `image/*` or `video/*` type that matches the bytes.

```dart
final file = await fastrelay.uploadFileDirect(
  await photo.readAsBytes(),
  'image/jpeg',
);
print(file.url);
```

For other content types, `uploadFile(bytes, filename)` uploads through the API as multipart.

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
    .listen((event) => print('video ${event.videoId}: ${event.type}'));
```

## Aggregated / notification feeds

For feeds configured with aggregation (notifications, grouped activity), use `getNotificationFeedActivities`, which returns `NotificationPage<FastrelayActivity>` with grouped entries and unseen/unread counts:

```dart
final notifications = await fastrelay.getNotificationFeedActivities(
  'notification',
  'john',
  query: {'limit': 25},
);

print('unseen: ${notifications.unseenCount}, unread: ${notifications.unreadCount}');
for (final group in notifications.groups) {
  print('${group.groupKey}: ${group.activityCount} activities');
}
```

## Error handling

Every non-2xx response throws `FastrelayApiError` with the parsed error envelope plus rate-limit headers:

```dart
try {
  await fastrelay.activities.get('act_missing');
} on FastrelayApiError catch (error) {
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

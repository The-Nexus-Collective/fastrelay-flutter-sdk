# FastRelay Feed Flutter SDK

Flutter SDK for FastRelay activity feeds.

- Feed-first API: `fastrelay.feed(group, id)`
- User and server auth support
- Automatic `camelCase` <-> `snake_case` JSON mapping
- Structured `FastRelayApiError` exceptions

## Install

```yaml
dependencies:
  fastrelay_feed_sdk:
    path: /Users/robertkoziej/src/fastrelay/fastrelay-sdk/flutter
```

## Quick start

```dart
import 'package:fastrelay_feed_sdk/fastrelay_feed_sdk.dart';

final fastrelay = FastRelayClient(
  apiKey: 'your_api_key',
  baseUrl: 'http://localhost:8080',
);

await fastrelay.connectUser(
  {
    'id': 'john',
    'displayName': 'John Doe',
  },
  'user_jwt_token',
);

final timeline = fastrelay.feed('timeline', 'john');
await timeline.getOrCreate();

await timeline.addActivity({
  'type': 'post',
  'text': 'Hello FastRelay!',
});

final page = await timeline.getActivities(
  query: {'limit': 25},
);
```

## Server auth example

```dart
final fastrelay = FastRelayClient(
  apiKey: 'your_api_key',
  apiSecret: 'your_api_secret',
  baseUrl: 'http://localhost:8080',
);

await fastrelay.tokens.issue({
  'userId': 'john',
  'role': 'user',
  'expiresIn': 3600,
});
```

## Main feed APIs

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

## Error handling

```dart
try {
  await fastrelay.activities.get('act_missing');
} on FastRelayApiError catch (error) {
  print('${error.status}: ${error.code} ${error.message}');
}
```

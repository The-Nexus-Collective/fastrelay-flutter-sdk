import 'dart:async';

import 'fastrelay_client.dart';
import 'models/models.dart';

class FastrelayFeed {
  FastrelayFeed(this._client, String group, String id)
    : group = group.trim(),
      feedId = id.trim() {
    if (this.group.isEmpty || feedId.isEmpty) {
      throw ArgumentError('feed(group, id) requires both group and id.');
    }
  }

  final FastrelayClient _client;
  final String group;
  final String feedId;

  String get id => '$group:$feedId';

  Stream<FastrelayRealtimeEvent> events({String? type}) {
    final realtime = _client.realtime;
    if (realtime == null) {
      throw StateError(
        'Realtime is not initialized. Call connectUser(..., realtime: true).',
      );
    }
    return realtime.eventsForFeed(id, type: type);
  }

  StreamSubscription<FastrelayRealtimeEvent> on(
    String type,
    void Function(FastrelayRealtimeEvent event) callback,
  ) {
    final normalizedType = type.trim();
    if (normalizedType.isEmpty) {
      throw ArgumentError('Event type must not be empty.');
    }
    return events(type: normalizedType).listen(callback);
  }

  Future<dynamic> getOrCreate({
    Map<String, dynamic> request = const {},
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.getOrCreateFeed(
      group,
      feedId,
      request: request,
      options: options,
    );
  }

  Future<dynamic> getActivities({
    Map<String, dynamic>? query,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.getFeedActivities(
      group,
      feedId,
      query: query,
      options: options,
    );
  }

  Future<CursorPage<FastrelayActivity>> getActivityList({
    Map<String, dynamic>? query,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.getFeedActivityList(
      group,
      feedId,
      query: query,
      options: options,
    );
  }

  Future<NotificationPage<FastrelayActivity>> getNotificationActivities({
    Map<String, dynamic>? query,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.getNotificationFeedActivities(
      group,
      feedId,
      query: query,
      options: options,
    );
  }

  Future<dynamic> getCapabilities({
    Map<String, dynamic>? query,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    final scopedQuery = <String, dynamic>{'feed': id, ...?query};
    return _client.getCapabilities(query: scopedQuery, options: options);
  }

  Future<dynamic> addActivity(
    Map<String, dynamic> activity, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    final feedName = id;
    final feeds = <String>[
      if (activity['feeds'] is Iterable)
        ...((activity['feeds'] as Iterable).map((entry) => entry.toString())),
    ];

    if (!feeds.contains(feedName)) {
      feeds.add(feedName);
    }

    final payload = <String, dynamic>{...activity, 'feeds': feeds};

    return _client.addActivity(payload, options: options);
  }

  Future<dynamic> delete({
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.deleteFeed(group, feedId, options: options);
  }

  Future<dynamic> setVisibility(
    String level, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.setFeedVisibility(group, feedId, level, options: options);
  }

  Future<dynamic> updateSettings(
    Map<String, dynamic> settings, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.updateFeedSettings(
      group,
      feedId,
      settings,
      options: options,
    );
  }

  Future<dynamic> addMember(
    String userId, {
    String role = 'member',
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.addFeedMember(group, feedId, {
      'userId': userId,
      'role': role,
    }, options: options);
  }

  Future<dynamic> removeMember(
    String userId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.removeFeedMember(group, feedId, userId, options: options);
  }

  Future<dynamic> listMembers({
    Map<String, dynamic>? query,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.listFeedMembers(
      group,
      feedId,
      query: query,
      options: options,
    );
  }

  Future<dynamic> follow(
    Object target, {
    int? activityCopyLimit,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.followFeed(group, feedId, {
      'target': target,
      ...?activityCopyLimit == null
          ? null
          : {'activityCopyLimit': activityCopyLimit},
    }, options: options);
  }

  Future<dynamic> batchFollow(
    List<Object> targets, {
    int? activityCopyLimit,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.batchFollowFeed(group, feedId, {
      'targets': targets,
      ...?activityCopyLimit == null
          ? null
          : {'activityCopyLimit': activityCopyLimit},
    }, options: options);
  }

  Future<dynamic> unfollow(
    Object target, {
    bool? keepHistory,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.unfollowFeed(
      group,
      feedId,
      target,
      keepHistory: keepHistory,
      options: options,
    );
  }

  Future<dynamic> listFollowers({
    Map<String, dynamic>? query,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.listFollowers(group, feedId, query: query, options: options);
  }

  Future<dynamic> listFollowing({
    Map<String, dynamic>? query,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.listFollowing(group, feedId, query: query, options: options);
  }

  Future<dynamic> listFollowRequests({
    Map<String, dynamic>? query,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.listFollowRequests(
      group,
      feedId,
      query: query,
      options: options,
    );
  }

  Future<dynamic> approveFollowRequest(
    String requestId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.approveFollowRequest(
      group,
      feedId,
      requestId,
      options: options,
    );
  }

  Future<dynamic> rejectFollowRequest(
    String requestId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.rejectFollowRequest(
      group,
      feedId,
      requestId,
      options: options,
    );
  }

  Future<FastrelayReaction> addReaction(
    String activityId, {
    required String type,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.addReaction(activityId, type: type, options: options);
  }

  Future<void> removeReaction(
    String activityId,
    String reactionId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.removeReaction(activityId, reactionId, options: options);
  }

  Future<FastrelayComment> addComment(
    String activityId, {
    required String text,
    String? parentId,
    List<String>? mentionedUsers,
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.addComment(
      activityId,
      text: text,
      parentId: parentId,
      mentionedUsers: mentionedUsers,
      options: options,
    );
  }

  Future<FastrelayBookmark> addBookmark(
    String activityId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.addBookmark(activityId, options: options);
  }

  Future<void> removeBookmark(
    String activityId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.removeBookmark(activityId, options: options);
  }

  Future<FastrelayFeedActivityPin> pinActivity(
    String activityId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.pinActivity(group, feedId, activityId, options: options);
  }

  Future<void> unpinActivity(
    String activityId, {
    FastrelayRequestOptions options = const FastrelayRequestOptions(),
  }) {
    return _client.unpinActivity(group, feedId, activityId, options: options);
  }
}

import 'dart:async';

import 'fastrelay_client.dart';
import 'models/models.dart';

class FastRelayFeed {
  FastRelayFeed(this._client, String group, String id)
    : group = group.trim(),
      feedId = id.trim() {
    if (this.group.isEmpty || feedId.isEmpty) {
      throw ArgumentError('feed(group, id) requires both group and id.');
    }
  }

  final FastRelayClient _client;
  final String group;
  final String feedId;

  String get id => '$group:$feedId';

  Stream<FastRelayRealtimeEvent> events({String? type}) {
    final realtime = _client.realtime;
    if (realtime == null) {
      throw StateError(
        'Realtime is not initialized. Call connectUser(..., realtime: true).',
      );
    }
    return realtime.eventsForFeed(id, type: type);
  }

  StreamSubscription<FastRelayRealtimeEvent> on(
    String type,
    void Function(FastRelayRealtimeEvent event) callback,
  ) {
    final normalizedType = type.trim();
    if (normalizedType.isEmpty) {
      throw ArgumentError('Event type must not be empty.');
    }
    return events(type: normalizedType).listen(callback);
  }

  Future<dynamic> getOrCreate({
    Map<String, dynamic> request = const {},
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
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
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.getFeedActivities(
      group,
      feedId,
      query: query,
      options: options,
    );
  }

  Future<CursorPage<FastRelayActivity>> getActivityList({
    Map<String, dynamic>? query,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.getFeedActivityList(
      group,
      feedId,
      query: query,
      options: options,
    );
  }

  Future<NotificationPage<FastRelayActivity>> getNotificationActivities({
    Map<String, dynamic>? query,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
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
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    final scopedQuery = <String, dynamic>{'feed': id, ...?query};
    return _client.getCapabilities(query: scopedQuery, options: options);
  }

  Future<dynamic> addActivity(
    Map<String, dynamic> activity, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
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
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.deleteFeed(group, feedId, options: options);
  }

  Future<dynamic> setVisibility(
    String level, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.setFeedVisibility(group, feedId, level, options: options);
  }

  Future<dynamic> updateSettings(
    Map<String, dynamic> settings, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
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
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.addFeedMember(group, feedId, {
      'userId': userId,
      'role': role,
    }, options: options);
  }

  Future<dynamic> removeMember(
    String userId, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.removeFeedMember(group, feedId, userId, options: options);
  }

  Future<dynamic> listMembers({
    Map<String, dynamic>? query,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
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
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
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
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
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
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
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
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.listFollowers(group, feedId, query: query, options: options);
  }

  Future<dynamic> listFollowing({
    Map<String, dynamic>? query,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.listFollowing(group, feedId, query: query, options: options);
  }

  Future<dynamic> listFollowRequests({
    Map<String, dynamic>? query,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
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
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
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
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.rejectFollowRequest(
      group,
      feedId,
      requestId,
      options: options,
    );
  }

  Future<FastRelayReaction> addReaction(
    String activityId, {
    required String type,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.addReaction(activityId, type: type, options: options);
  }

  Future<void> removeReaction(
    String activityId,
    String reactionId, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.removeReaction(activityId, reactionId, options: options);
  }

  Future<FastRelayComment> addComment(
    String activityId, {
    required String text,
    String? parentId,
    List<String>? mentionedUsers,
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.addComment(
      activityId,
      text: text,
      parentId: parentId,
      mentionedUsers: mentionedUsers,
      options: options,
    );
  }

  Future<FastRelayBookmark> addBookmark(
    String activityId, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.addBookmark(activityId, options: options);
  }

  Future<void> removeBookmark(
    String activityId, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.removeBookmark(activityId, options: options);
  }

  Future<FastRelayFeedActivityPin> pinActivity(
    String activityId, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.pinActivity(group, feedId, activityId, options: options);
  }

  Future<void> unpinActivity(
    String activityId, {
    FastRelayRequestOptions options = const FastRelayRequestOptions(),
  }) {
    return _client.unpinActivity(group, feedId, activityId, options: options);
  }
}

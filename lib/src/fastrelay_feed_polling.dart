import 'dart:async';

import 'fastrelay_client.dart';
import 'models/models.dart';

class FeedPollingService {
  FeedPollingService({
    required FastRelayClient client,
    Duration activeInterval = const Duration(seconds: 15),
    Duration backgroundInterval = const Duration(seconds: 60),
  }) : _client = client,
       _activeInterval = activeInterval,
       _backgroundInterval = backgroundInterval;

  final FastRelayClient _client;
  final Duration _activeInterval;
  final Duration _backgroundInterval;

  final Map<String, _PollerBase> _pollers = {};
  bool _paused = false;

  Stream<CursorPage<FastRelayActivity>> pollFeed(
    String group,
    String id, {
    int limit = 25,
  }) {
    final key = '${group.trim()}:${id.trim()}#feed';
    final existing = _pollers[key];
    if (existing is _FeedPoller) {
      return existing.stream;
    }

    existing?.dispose();

    final poller = _FeedPoller(
      client: _client,
      group: group,
      id: id,
      limit: limit,
      interval: _paused ? _backgroundInterval : _activeInterval,
    );

    _pollers[key] = poller;
    return poller.stream;
  }

  Stream<NotificationPage<FastRelayActivity>> pollNotifications(
    String group,
    String id, {
    int limit = 25,
  }) {
    final key = '${group.trim()}:${id.trim()}#notification';
    final existing = _pollers[key];
    if (existing is _NotificationPoller) {
      return existing.stream;
    }

    existing?.dispose();

    final poller = _NotificationPoller(
      client: _client,
      group: group,
      id: id,
      limit: limit,
      interval: _paused ? _backgroundInterval : _activeInterval,
    );

    _pollers[key] = poller;
    return poller.stream;
  }

  void pause() {
    _paused = true;
    for (final poller in _pollers.values) {
      poller.setInterval(_backgroundInterval);
    }
  }

  void resume() {
    _paused = false;
    for (final poller in _pollers.values) {
      poller.setInterval(_activeInterval);
    }
  }

  void stopPolling(String group, String id) {
    final feedKey = '${group.trim()}:${id.trim()}#feed';
    final notificationKey = '${group.trim()}:${id.trim()}#notification';

    _pollers.remove(feedKey)?.dispose();
    _pollers.remove(notificationKey)?.dispose();
  }

  void dispose() {
    for (final poller in _pollers.values) {
      poller.dispose();
    }
    _pollers.clear();
  }
}

abstract class _PollerBase {
  void setInterval(Duration interval);
  void dispose();
}

class _FeedPoller implements _PollerBase {
  _FeedPoller({
    required this.client,
    required this.group,
    required this.id,
    required this.limit,
    required Duration interval,
  }) {
    _startTimer(interval);
    unawaited(_poll());
  }

  final FastRelayClient client;
  final String group;
  final String id;
  final int limit;

  final _controller =
      StreamController<CursorPage<FastRelayActivity>>.broadcast();
  Timer? _timer;
  bool _isPolling = false;

  Stream<CursorPage<FastRelayActivity>> get stream => _controller.stream;

  @override
  void setInterval(Duration interval) {
    _startTimer(interval);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    unawaited(_controller.close());
  }

  void _startTimer(Duration interval) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) {
      unawaited(_poll());
    });
  }

  Future<void> _poll() async {
    if (_controller.isClosed || _isPolling) {
      return;
    }

    _isPolling = true;
    try {
      final page = await client.getFeedActivityList(
        group,
        id,
        query: {'limit': limit},
      );
      if (!_controller.isClosed) {
        _controller.add(page);
      }
    } catch (error, stackTrace) {
      if (!_controller.isClosed) {
        _controller.addError(error, stackTrace);
      }
    } finally {
      _isPolling = false;
    }
  }
}

class _NotificationPoller implements _PollerBase {
  _NotificationPoller({
    required this.client,
    required this.group,
    required this.id,
    required this.limit,
    required Duration interval,
  }) {
    _startTimer(interval);
    unawaited(_poll());
  }

  final FastRelayClient client;
  final String group;
  final String id;
  final int limit;

  final _controller =
      StreamController<NotificationPage<FastRelayActivity>>.broadcast();
  Timer? _timer;
  bool _isPolling = false;

  Stream<NotificationPage<FastRelayActivity>> get stream => _controller.stream;

  @override
  void setInterval(Duration interval) {
    _startTimer(interval);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    unawaited(_controller.close());
  }

  void _startTimer(Duration interval) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) {
      unawaited(_poll());
    });
  }

  Future<void> _poll() async {
    if (_controller.isClosed || _isPolling) {
      return;
    }

    _isPolling = true;
    try {
      final page = await client.getNotificationFeedActivities(
        group,
        id,
        query: {'limit': limit},
      );
      if (!_controller.isClosed) {
        _controller.add(page);
      }
    } catch (error, stackTrace) {
      if (!_controller.isClosed) {
        _controller.addError(error, stackTrace);
      }
    } finally {
      _isPolling = false;
    }
  }
}

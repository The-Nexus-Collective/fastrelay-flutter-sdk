import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:web_socket_client/web_socket_client.dart' as ws;

import 'fastrelay_client.dart';
import 'models/connection_established.dart';
import 'models/chat_event.dart';
import 'models/realtime_event.dart';
import 'models/video.dart';
import 'utils.dart';

typedef FastrelayTokenProvider = Future<String> Function();

typedef FastrelayRealtimeFactory =
    FastrelayRealtime Function({
      required FastrelayClient client,
      required String token,
      FastrelayTokenProvider? tokenProvider,
      bool maintainBackgroundConnection,
      FastrelayRealtimeSocketFactory? socketFactory,
    });

typedef FastrelayRealtimeSocketFactory =
    FastrelayRealtimeSocket Function(Uri uri);

abstract class FastrelayRealtimeSocket {
  Stream<String> get messages;
  Stream<FastrelayRealtimeSocketState> get connection;

  void send(String message);
  void close();
}

enum FastrelayRealtimeSocketStatus {
  connecting,
  connected,
  reconnecting,
  disconnected,
}

class FastrelayRealtimeSocketState {
  const FastrelayRealtimeSocketState({
    required this.status,
    this.closeCode,
    this.reason,
    this.error,
  });

  final FastrelayRealtimeSocketStatus status;
  final int? closeCode;
  final String? reason;
  final Object? error;
}

class FastrelayRealtime with WidgetsBindingObserver {
  FastrelayRealtime({
    required FastrelayClient client,
    required String token,
    FastrelayTokenProvider? tokenProvider,
    bool maintainBackgroundConnection = false,
    FastrelayRealtimeSocketFactory? socketFactory,
    Duration subscribeDebounce = const Duration(milliseconds: 50),
    Duration deadConnectionTimeout = const Duration(seconds: 90),
    Duration reconnectInitialDelay = const Duration(seconds: 1),
    Duration reconnectMaxDelay = const Duration(seconds: 30),
    DateTime Function()? now,
    math.Random? random,
  }) : _client = client,
       _token = token,
       _tokenProvider = tokenProvider,
       _maintainBackgroundConnection = maintainBackgroundConnection,
       _socketFactory =
           socketFactory ?? ((uri) => _WebSocketClientAdapter(uri)),
       _subscribeDebounce = subscribeDebounce,
       _deadConnectionTimeout = deadConnectionTimeout,
       _reconnectInitialDelay = reconnectInitialDelay,
       _reconnectMaxDelay = reconnectMaxDelay,
       _now = now ?? (() => DateTime.now().toUtc()),
       _random = random ?? math.Random();

  static const int _maxRecentEventIds = 1000;

  final FastrelayClient _client;
  final FastrelayTokenProvider? _tokenProvider;
  final bool _maintainBackgroundConnection;
  final FastrelayRealtimeSocketFactory _socketFactory;
  final Duration _subscribeDebounce;
  final Duration _deadConnectionTimeout;
  final Duration _reconnectInitialDelay;
  final Duration _reconnectMaxDelay;
  final DateTime Function() _now;
  final math.Random _random;

  final Set<String> _desiredFeeds = <String>{};
  final Set<String> _acknowledgedFeeds = <String>{};
  final Set<String> _pendingSubscribes = <String>{};
  final Set<String> _pendingUnsubscribes = <String>{};
  final LinkedHashSet<String> _recentEventIds = LinkedHashSet<String>();
  final Map<String, _FeedStreamEntry> _feedStreams = {};

  final StreamController<FastrelayRealtimeEvent> _eventController =
      StreamController<FastrelayRealtimeEvent>.broadcast();
  final StreamController<FastrelayConnectionState> _stateController =
      StreamController<FastrelayConnectionState>.broadcast();
  final StreamController<FastrelayRealtimeError> _errorController =
      StreamController<FastrelayRealtimeError>.broadcast();
  final StreamController<FastrelayVideoStatusEvent> _videoStatusController =
      StreamController<FastrelayVideoStatusEvent>.broadcast();
  final StreamController<FastrelayChatEvent> _chatEventController =
      StreamController<FastrelayChatEvent>.broadcast();
  final StreamController<FastrelayConnectionEstablished>
  _establishedController =
      StreamController<FastrelayConnectionEstablished>.broadcast();

  FastrelayRealtimeSocket? _socket;
  StreamSubscription<String>? _messageSubscription;
  StreamSubscription<FastrelayRealtimeSocketState>? _connectionSubscription;

  Timer? _subscribeBatchTimer;
  Timer? _reconnectTimer;
  Timer? _deadConnectionTimer;

  DateTime? _lastServerMessageAt;
  String _token;

  FastrelayConnectionState _connectionState =
      FastrelayConnectionState.disconnected;

  bool _shouldBeConnected = false;
  bool _isDisposed = false;
  bool _observerRegistered = false;
  bool _lifecycleSuspended = false;
  bool _awaitingTokenRefresh = false;
  bool _invalidTokenRefreshAttempted = false;
  bool _hasConnectedAtLeastOnce = false;
  bool _hasEstablishedAtLeastOnce = false;
  bool _presenceRequested = false;

  int _generation = 0;
  int _reconnectAttempt = 0;

  Stream<FastrelayRealtimeEvent> get events => _eventController.stream;

  Stream<FastrelayConnectionState> get connectionStateStream =>
      _stateController.stream;

  Stream<FastrelayRealtimeError> get errors => _errorController.stream;

  Stream<FastrelayVideoStatusEvent> get videoStatusEvents =>
      _videoStatusController.stream;

  /// Chat events (`message.new`, `typing.start`, `presence.changed`, ...).
  /// These carry no `feedId` and never appear on [events] or feed streams.
  /// Events are deduplicated by `eventId`; unknown types are delivered too.
  Stream<FastrelayChatEvent> get chatEvents => _chatEventController.stream;

  /// Emits on every successful (re)connect. Its `serverTime` is the
  /// `syncChat` anchor: keep it on the first connect, and on a reconnect call
  /// `syncChat(since: anchor)` and store the response's `serverTime`.
  Stream<FastrelayConnectionEstablished> get connectionEstablished =>
      _establishedController.stream;

  FastrelayConnectionState get connectionState => _connectionState;

  void updateToken(String token) {
    _token = token;
  }

  void onBaseUrlChanged() {
    if (!_shouldBeConnected || _isDisposed || _lifecycleSuspended) {
      return;
    }
    _scheduleReconnect(immediate: true);
  }

  Future<void> connect() async {
    if (_isDisposed) {
      return;
    }

    _shouldBeConnected = true;
    _ensureLifecycleObserver();
    _cancelReconnectTimer();

    final shouldReconnect = _hasConnectedAtLeastOnce;
    await _openSocket(isReconnect: shouldReconnect);
  }

  void disconnect({bool clearSubscriptions = false}) {
    if (_isDisposed) {
      return;
    }

    _shouldBeConnected = false;
    _lifecycleSuspended = false;
    _awaitingTokenRefresh = false;

    _cancelReconnectTimer();
    _cancelSubscribeBatch();
    _pendingSubscribes.clear();
    _pendingUnsubscribes.clear();

    _closeSocketResources();
    _acknowledgedFeeds.clear();

    if (clearSubscriptions) {
      _desiredFeeds.clear();
      _clearFeedStreams();
      _presenceRequested = false;
    }

    _setConnectionState(FastrelayConnectionState.disconnected);
  }

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;
    _shouldBeConnected = false;
    _lifecycleSuspended = false;
    _presenceRequested = false;

    _cancelReconnectTimer();
    _cancelSubscribeBatch();
    _stopDeadConnectionMonitor();

    await _messageSubscription?.cancel();
    _messageSubscription = null;

    await _connectionSubscription?.cancel();
    _connectionSubscription = null;

    _socket?.close();
    _socket = null;

    _removeLifecycleObserver();

    for (final entry in _feedStreams.values) {
      await entry.controller.close();
    }
    _feedStreams.clear();

    await _eventController.close();
    await _stateController.close();
    await _errorController.close();
    await _videoStatusController.close();
    await _chatEventController.close();
    await _establishedController.close();
  }

  /// Tells the other members that the user started typing. Fire-and-forget:
  /// returns `false` without queueing when not connected.
  bool startTyping(String conversationId) {
    return _sendChatMessage('typing.start', conversationId);
  }

  /// Tells the other members that the user stopped typing. Fire-and-forget:
  /// returns `false` without queueing when not connected.
  bool stopTyping(String conversationId) {
    return _sendChatMessage('typing.stop', conversationId);
  }

  /// Marks messages up to [seq] (must be > 0) delivered. Fire-and-forget:
  /// returns `false` without queueing when not connected.
  bool markDelivered(String conversationId, int seq) {
    return _sendChatMessage('message.delivered', conversationId, seq: seq);
  }

  /// Marks the conversation read up to [seq] (must be > 0), or up to the
  /// latest message when omitted. Fire-and-forget: returns `false` without
  /// queueing when not connected — fall back to
  /// `FastrelayClient.markConversationRead`.
  bool markRead(String conversationId, {int? seq}) {
    return _sendChatMessage('conversation.read', conversationId, seq: seq);
  }

  /// Opts this connection into presence tracking. Sent now when connected
  /// and re-sent after every reconnect. There is no stop message: the user
  /// goes offline when the connection closes. Cleared by [dispose] and by
  /// `disconnect(clearSubscriptions: true)`.
  void startPresence() {
    if (_isDisposed) {
      return;
    }
    _presenceRequested = true;
    if (_connectionState == FastrelayConnectionState.connected) {
      _send({'type': 'presence.start'});
    }
  }

  bool _sendChatMessage(String type, String conversationId, {int? seq}) {
    final normalizedConversationId = conversationId.trim();
    if (normalizedConversationId.isEmpty) {
      throw ArgumentError.value(
        conversationId,
        'conversationId',
        'must not be blank.',
      );
    }
    if (seq != null && seq <= 0) {
      throw ArgumentError.value(seq, 'seq', 'must be greater than 0.');
    }

    if (_isDisposed || _connectionState != FastrelayConnectionState.connected) {
      return false;
    }

    return _send({
      'type': type,
      'conversationId': normalizedConversationId,
      'seq': ?seq,
    });
  }

  Stream<FastrelayRealtimeEvent> eventsForFeed(String feedId, {String? type}) {
    if (_isDisposed) {
      return Stream<FastrelayRealtimeEvent>.error(
        StateError('FastrelayRealtime is disposed.'),
      );
    }

    final normalizedFeedId = feedId.trim();
    if (normalizedFeedId.isEmpty) {
      return Stream<FastrelayRealtimeEvent>.error(
        ArgumentError('feedId must not be empty.'),
      );
    }

    final entry = _feedStreams.putIfAbsent(
      normalizedFeedId,
      () => _createFeedStreamEntry(normalizedFeedId),
    );

    final baseStream = entry.controller.stream;
    if (type == null || type.trim().isEmpty) {
      return baseStream;
    }

    final normalizedType = type.trim();
    return baseStream.where((event) => event.type == normalizedType);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposed || _maintainBackgroundConnection) {
      return;
    }

    switch (state) {
      case AppLifecycleState.resumed:
        _resumeFromBackground();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _suspendForBackground();
        break;
    }
  }

  _FeedStreamEntry _createFeedStreamEntry(String feedId) {
    return _FeedStreamEntry(
      controller: StreamController<FastrelayRealtimeEvent>.broadcast(
        onListen: () {
          if (_isDisposed) {
            return;
          }
          _desiredFeeds.add(feedId);
          _pendingUnsubscribes.remove(feedId);
          _pendingSubscribes.add(feedId);
          _scheduleSubscribeBatch();
        },
        onCancel: () {
          if (_isDisposed) {
            return;
          }

          final streamEntry = _feedStreams[feedId];
          if (streamEntry == null || streamEntry.controller.hasListener) {
            return;
          }

          _desiredFeeds.remove(feedId);
          _acknowledgedFeeds.remove(feedId);
          _pendingSubscribes.remove(feedId);
          _pendingUnsubscribes.add(feedId);
          _scheduleSubscribeBatch();
        },
      ),
    );
  }

  void _ensureLifecycleObserver() {
    if (_maintainBackgroundConnection || _observerRegistered) {
      return;
    }

    try {
      WidgetsBinding.instance.addObserver(this);
      _observerRegistered = true;
    } catch (_) {
      _observerRegistered = false;
    }
  }

  void _removeLifecycleObserver() {
    if (!_observerRegistered) {
      return;
    }

    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {
      // Intentionally ignored. Some tests do not initialize a binding.
    }
    _observerRegistered = false;
  }

  Future<void> _openSocket({required bool isReconnect}) async {
    if (_isDisposed || !_shouldBeConnected || _lifecycleSuspended) {
      return;
    }

    // Any reconnect (network drop, dead-connection timeout, resume) may run
    // long after the token expired; the server rejects that handshake with
    // 4002, so refresh up front whenever a provider can.
    if (_tokenProvider != null && _isTokenExpired(_token)) {
      _awaitingTokenRefresh = true;
    }

    if (_awaitingTokenRefresh) {
      final refreshed = await _refreshToken();
      if (!refreshed) {
        _scheduleReconnect();
        return;
      }
      _awaitingTokenRefresh = false;
    }

    final token = _token.trim();
    if (token.isEmpty) {
      _emitError(
        FastrelayRealtimeError(
          code: 'MISSING_TOKEN',
          message: 'Realtime connection requires a non-empty token.',
          retryable: false,
        ),
      );
      _setConnectionState(FastrelayConnectionState.disconnected);
      return;
    }

    await _messageSubscription?.cancel();
    _messageSubscription = null;

    await _connectionSubscription?.cancel();
    _connectionSubscription = null;

    _socket?.close();
    _socket = null;

    _stopDeadConnectionMonitor();

    final generation = ++_generation;

    _setConnectionState(
      isReconnect
          ? FastrelayConnectionState.reconnecting
          : FastrelayConnectionState.connecting,
    );

    final uri = _buildRealtimeUri(token);
    final socket = _socketFactory(uri);
    _socket = socket;

    _lastServerMessageAt = _now();
    _startDeadConnectionMonitor();

    _messageSubscription = socket.messages.listen(
      (message) => _handleRawMessage(message, generation),
      onError: (Object error, StackTrace stackTrace) {
        if (generation != _generation || _isDisposed) {
          return;
        }
        _emitError(
          FastrelayRealtimeError(
            code: 'SOCKET_MESSAGE_STREAM_ERROR',
            message: 'Realtime message stream failed.',
            retryable: true,
            cause: error,
            stackTrace: stackTrace,
          ),
        );
      },
    );

    _connectionSubscription = socket.connection.listen(
      (state) => _handleSocketState(state, generation),
      onError: (Object error, StackTrace stackTrace) {
        if (generation != _generation || _isDisposed) {
          return;
        }
        _emitError(
          FastrelayRealtimeError(
            code: 'SOCKET_CONNECTION_STREAM_ERROR',
            message: 'Realtime connection stream failed.',
            retryable: true,
            cause: error,
            stackTrace: stackTrace,
          ),
        );
      },
    );
  }

  void _handleSocketState(FastrelayRealtimeSocketState state, int generation) {
    if (_isDisposed || generation != _generation) {
      return;
    }

    switch (state.status) {
      case FastrelayRealtimeSocketStatus.connecting:
        if (_hasConnectedAtLeastOnce) {
          _setConnectionState(FastrelayConnectionState.reconnecting);
        } else {
          _setConnectionState(FastrelayConnectionState.connecting);
        }
        break;
      case FastrelayRealtimeSocketStatus.connected:
        _onConnected(generation);
        break;
      case FastrelayRealtimeSocketStatus.reconnecting:
        _setConnectionState(FastrelayConnectionState.reconnecting);
        break;
      case FastrelayRealtimeSocketStatus.disconnected:
        _onDisconnected(
          generation,
          closeCode: state.closeCode,
          reason: state.reason,
          error: state.error,
        );
        break;
    }
  }

  void _onConnected(int generation) {
    if (_isDisposed || generation != _generation) {
      return;
    }

    _reconnectAttempt = 0;
    _invalidTokenRefreshAttempted = false;
    _cancelReconnectTimer();
    _setConnectionState(FastrelayConnectionState.connected);

    _hasConnectedAtLeastOnce = true;

    _queueResubscribe();

    if (_presenceRequested) {
      _send({'type': 'presence.start'});
    }
  }

  void _onDisconnected(
    int generation, {
    required int? closeCode,
    required String? reason,
    required Object? error,
  }) {
    if (_isDisposed || generation != _generation) {
      return;
    }

    _stopDeadConnectionMonitor();
    _acknowledgedFeeds.clear();
    _setConnectionState(FastrelayConnectionState.disconnected);

    if (_lifecycleSuspended || !_shouldBeConnected) {
      return;
    }

    // The server answers an expired JWT on the handshake with 4002, not 4003,
    // so give the provider one shot at a fresh token before treating 4002 as
    // fatal. A second 4002 in a row means the token really is invalid.
    if (closeCode == 4002 &&
        _tokenProvider != null &&
        !_invalidTokenRefreshAttempted) {
      _invalidTokenRefreshAttempted = true;
      _awaitingTokenRefresh = true;
      _scheduleReconnect(immediate: true);
      return;
    }

    if (closeCode == 4029 || closeCode == 4002) {
      _shouldBeConnected = false;
      _emitError(
        FastrelayRealtimeError(
          code: closeCode == 4029
              ? 'CONNECTION_LIMIT_EXCEEDED'
              : 'INVALID_TOKEN',
          message: closeCode == 4029
              ? 'Realtime connection limit exceeded for this user or app.'
              : 'Realtime token is invalid.',
          retryable: false,
          closeCode: closeCode,
          details: reason,
          cause: error,
        ),
      );
      return;
    }

    if (closeCode == 4003) {
      if (_tokenProvider == null) {
        _shouldBeConnected = false;
        _emitError(
          FastrelayRealtimeError(
            code: 'TOKEN_EXPIRED',
            message:
                'Realtime token expired and no tokenProvider was configured.',
            retryable: false,
            closeCode: closeCode,
            details: reason,
            cause: error,
          ),
        );
        return;
      }
      _awaitingTokenRefresh = true;
      _scheduleReconnect(immediate: true);
      return;
    }

    _emitError(
      FastrelayRealtimeError(
        code: 'CONNECTION_DROPPED',
        message: 'Realtime connection dropped.',
        retryable: true,
        closeCode: closeCode,
        details: reason,
        cause: error,
      ),
    );
    _scheduleReconnect();
  }

  void _handleRawMessage(String rawMessage, int generation) {
    if (_isDisposed || generation != _generation) {
      return;
    }

    _lastServerMessageAt = _now();

    final decoded = parseJsonSafely(rawMessage);
    if (decoded is! Map) {
      return;
    }

    final normalized = _toStringDynamicMap(decoded);
    if (normalized.isEmpty) {
      return;
    }

    final type = normalized['type']?.toString() ?? '';

    switch (type) {
      case 'connection.established':
        _emitEstablished(normalized);
        return;
      case 'heartbeat':
      case 'server.going_away':
        return;
      case 'subscribe.success':
        _acknowledgedFeeds.addAll(_toStringSet(normalized['feeds']));
        return;
      case 'unsubscribe.success':
        _acknowledgedFeeds.removeAll(_toStringSet(normalized['feeds']));
        return;
      case 'subscribe.error':
      case 'error':
        _emitControlError(type, normalized);
        return;
      case 'video.ready':
      case 'video.failed':
        _dispatchVideoStatus(normalized);
        return;
    }

    if (type.isEmpty || _isControlMessageType(type)) {
      return;
    }

    // Feed events carry a `feedId`; chat events (`ChatEvent` on the server)
    // never do.
    if (normalized['feedId'] == null) {
      _handleChatEvent(normalized);
      return;
    }

    final event = FastrelayRealtimeEvent.fromJson(normalized);
    if (event.type.isEmpty || event.feedId.isEmpty) {
      return;
    }

    if (event.eventId.isNotEmpty && !_trackEventId(event.eventId)) {
      return;
    }

    _dispatchEvent(event);
  }

  static bool _isControlMessageType(String type) {
    return type.startsWith('subscribe.') ||
        type.startsWith('unsubscribe.') ||
        type.startsWith('video.');
  }

  void _handleChatEvent(Map<String, dynamic> payload) {
    if (_isDisposed || _chatEventController.isClosed) {
      return;
    }

    final FastrelayChatEvent event;
    try {
      event = FastrelayChatEvent.fromJson(payload);
    } catch (error, stackTrace) {
      _emitError(
        FastrelayRealtimeError(
          code: 'CHAT_EVENT_PARSE_FAILED',
          message: 'Failed to parse realtime chat event.',
          retryable: true,
          details: payload,
          cause: error,
          stackTrace: stackTrace,
        ),
      );
      return;
    }

    if (event.type.isEmpty) {
      return;
    }

    if (event.eventId.isNotEmpty && !_trackEventId(event.eventId)) {
      return;
    }

    _chatEventController.add(event);
  }

  void _dispatchVideoStatus(Map<String, dynamic> payload) {
    if (_isDisposed || _videoStatusController.isClosed) {
      return;
    }

    final event = FastrelayVideoStatusEvent.fromJson(payload);
    if (event.videoId.isEmpty) {
      return;
    }

    _videoStatusController.add(event);
  }

  void _emitControlError(String type, Map<String, dynamic> payload) {
    final errorPayload = payload['error'];
    final errorMap = _toStringDynamicMap(errorPayload);

    final code =
        errorMap['code']?.toString() ??
        (type == 'subscribe.error' ? 'SUBSCRIBE_ERROR' : 'REALTIME_ERROR');

    final message =
        errorMap['message']?.toString() ??
        (type == 'subscribe.error'
            ? 'Feed subscription failed.'
            : 'Realtime error received from server.');

    _emitError(
      FastrelayRealtimeError(
        code: code,
        message: message,
        retryable:
            code != 'CONNECTION_LIMIT_EXCEEDED' && code != 'INVALID_TOKEN',
        details: errorMap['details'],
        hint: errorMap['hint']?.toString(),
      ),
    );
  }

  void _queueResubscribe() {
    for (final feed in _desiredFeeds) {
      if (!_acknowledgedFeeds.contains(feed)) {
        _pendingSubscribes.add(feed);
      }
    }
    _scheduleSubscribeBatch(immediate: true);
  }

  void _scheduleSubscribeBatch({bool immediate = false}) {
    if (_isDisposed) {
      return;
    }

    if (immediate) {
      _cancelSubscribeBatch();
      _flushSubscriptionBatch();
      return;
    }

    _subscribeBatchTimer ??= Timer(_subscribeDebounce, () {
      _subscribeBatchTimer = null;
      _flushSubscriptionBatch();
    });
  }

  void _flushSubscriptionBatch() {
    if (_isDisposed || _connectionState != FastrelayConnectionState.connected) {
      return;
    }

    if (_pendingSubscribes.isNotEmpty) {
      final feeds = _pendingSubscribes.toList()..sort();
      _pendingSubscribes.clear();
      _send({'type': 'subscribe', 'feeds': feeds});
    }

    if (_pendingUnsubscribes.isNotEmpty) {
      final feeds = _pendingUnsubscribes.toList()..sort();
      _pendingUnsubscribes.clear();
      _send({'type': 'unsubscribe', 'feeds': feeds});
    }
  }

  bool _send(Map<String, dynamic> payload) {
    final socket = _socket;
    if (socket == null || _isDisposed) {
      return false;
    }

    try {
      socket.send(jsonEncode(payload));
      return true;
    } catch (error, stackTrace) {
      _emitError(
        FastrelayRealtimeError(
          code: 'SEND_FAILED',
          message: 'Failed to send realtime message.',
          retryable: true,
          cause: error,
          stackTrace: stackTrace,
          details: payload,
        ),
      );
      return false;
    }
  }

  void _dispatchEvent(FastrelayRealtimeEvent event) {
    if (_isDisposed || _eventController.isClosed) {
      return;
    }

    _eventController.add(event);

    final feedEntry = _feedStreams[event.feedId];
    if (feedEntry == null || feedEntry.controller.isClosed) {
      return;
    }

    feedEntry.controller.add(event);
  }

  bool _trackEventId(String eventId) {
    if (_recentEventIds.contains(eventId)) {
      return false;
    }

    _recentEventIds.add(eventId);
    if (_recentEventIds.length > _maxRecentEventIds) {
      _recentEventIds.remove(_recentEventIds.first);
    }
    return true;
  }

  void _setConnectionState(FastrelayConnectionState state) {
    if (_connectionState == state || _stateController.isClosed) {
      _connectionState = state;
      return;
    }

    _connectionState = state;
    _stateController.add(state);
  }

  void _emitEstablished(Map<String, dynamic> payload) {
    final isReconnect = _hasEstablishedAtLeastOnce;
    _hasEstablishedAtLeastOnce = true;
    if (_establishedController.isClosed) {
      return;
    }
    final serverTimeText = payload['serverTime']?.toString();
    _establishedController.add(
      FastrelayConnectionEstablished(
        connectionId: payload['connectionId']?.toString() ?? '',
        serverTime: serverTimeText == null
            ? null
            : DateTime.tryParse(serverTimeText)?.toUtc(),
        isReconnect: isReconnect,
      ),
    );
  }

  void _emitError(FastrelayRealtimeError error) {
    if (_errorController.isClosed || _isDisposed) {
      return;
    }
    _errorController.add(error);
  }

  void _startDeadConnectionMonitor() {
    _stopDeadConnectionMonitor();

    final frequency = Duration(
      milliseconds: math.max(
        1000,
        (_deadConnectionTimeout.inMilliseconds / 3).round(),
      ),
    );

    _deadConnectionTimer = Timer.periodic(frequency, (_) {
      if (_isDisposed || _lifecycleSuspended || !_shouldBeConnected) {
        return;
      }

      final lastMessageAt = _lastServerMessageAt;
      if (lastMessageAt == null) {
        return;
      }

      final silentFor = _now().difference(lastMessageAt);
      if (silentFor < _deadConnectionTimeout) {
        return;
      }

      _emitError(
        FastrelayRealtimeError(
          code: 'DEAD_CONNECTION_TIMEOUT',
          message:
              'No realtime heartbeat/messages received within the dead connection timeout.',
          retryable: true,
        ),
      );

      _scheduleReconnect(immediate: true);
    });
  }

  void _stopDeadConnectionMonitor() {
    _deadConnectionTimer?.cancel();
    _deadConnectionTimer = null;
  }

  void _scheduleReconnect({bool immediate = false}) {
    if (_isDisposed || !_shouldBeConnected || _lifecycleSuspended) {
      return;
    }

    if (_reconnectTimer != null) {
      return;
    }

    final delay = immediate ? Duration.zero : _nextReconnectDelay();

    _setConnectionState(FastrelayConnectionState.reconnecting);

    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      unawaited(_openSocket(isReconnect: true));
    });
  }

  Duration _nextReconnectDelay() {
    final exponent = math.min(_reconnectAttempt, 10);
    final multiplier = math.pow(2, exponent).toDouble();
    final rawDelayMs = (_reconnectInitialDelay.inMilliseconds * multiplier)
        .round();

    final cappedDelayMs = math.min(
      rawDelayMs,
      _reconnectMaxDelay.inMilliseconds,
    );

    final jitter = 0.8 + (_random.nextDouble() * 0.4);
    final jitteredDelayMs = math.max(1, (cappedDelayMs * jitter).round());

    _reconnectAttempt += 1;

    return Duration(milliseconds: jitteredDelayMs);
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _cancelSubscribeBatch() {
    _subscribeBatchTimer?.cancel();
    _subscribeBatchTimer = null;
  }

  void _closeSocketResources() {
    _stopDeadConnectionMonitor();

    unawaited(_messageSubscription?.cancel());
    _messageSubscription = null;

    unawaited(_connectionSubscription?.cancel());
    _connectionSubscription = null;

    _socket?.close();
    _socket = null;
  }

  Future<bool> _refreshToken() async {
    final tokenProvider = _tokenProvider;
    if (tokenProvider == null) {
      _emitError(
        FastrelayRealtimeError(
          code: 'TOKEN_PROVIDER_MISSING',
          message:
              'Realtime token refresh requested but tokenProvider is null.',
          retryable: false,
        ),
      );
      return false;
    }

    try {
      final token = await tokenProvider();
      if (token.trim().isEmpty) {
        throw StateError('tokenProvider returned an empty token.');
      }

      _token = token;
      _client.setToken(token);
      return true;
    } catch (error, stackTrace) {
      _emitError(
        FastrelayRealtimeError(
          code: 'TOKEN_REFRESH_FAILED',
          message: 'Failed to refresh realtime token.',
          retryable: true,
          cause: error,
          stackTrace: stackTrace,
        ),
      );
      return false;
    }
  }

  Uri _buildRealtimeUri(String token) {
    final httpUri = toAbsoluteUrl(_client.baseUrl, '/v1/realtime', {
      'token': token,
    });

    final scheme = httpUri.scheme == 'https' ? 'wss' : 'ws';
    return httpUri.replace(scheme: scheme);
  }

  void _suspendForBackground() {
    if (_isDisposed || !_shouldBeConnected || _lifecycleSuspended) {
      return;
    }

    _lifecycleSuspended = true;
    _cancelReconnectTimer();
    _closeSocketResources();
    _acknowledgedFeeds.clear();
    _setConnectionState(FastrelayConnectionState.disconnected);
  }

  void _resumeFromBackground() {
    if (_isDisposed || !_lifecycleSuspended) {
      return;
    }

    _lifecycleSuspended = false;

    if (!_shouldBeConnected) {
      return;
    }

    _scheduleReconnect(immediate: true);
  }

  bool _isTokenExpired(String token) {
    final parts = token.split('.');
    if (parts.length < 2) {
      return false;
    }

    try {
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final decoded = jsonDecode(payload);
      if (decoded is! Map) {
        return false;
      }

      final exp = decoded['exp'];
      final expSeconds = exp is int
          ? exp
          : exp is num
          ? exp.toInt()
          : int.tryParse('$exp');

      if (expSeconds == null) {
        return false;
      }

      final expiresAt = DateTime.fromMillisecondsSinceEpoch(
        expSeconds * 1000,
        isUtc: true,
      );

      return _now().isAfter(expiresAt);
    } catch (_) {
      return false;
    }
  }

  void _clearFeedStreams() {
    final entries = _feedStreams.values.toList(growable: false);
    _feedStreams.clear();

    for (final entry in entries) {
      unawaited(entry.controller.close());
    }
  }

  static Map<String, dynamic> _toStringDynamicMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }
    if (value is Map) {
      return value.map((key, entryValue) => MapEntry('$key', entryValue));
    }
    return const {};
  }

  static Set<String> _toStringSet(Object? value) {
    if (value is! Iterable) {
      return const <String>{};
    }

    return value
        .map((entry) => entry?.toString() ?? '')
        .where((entry) => entry.isNotEmpty)
        .toSet();
  }
}

class _FeedStreamEntry {
  _FeedStreamEntry({required this.controller});

  final StreamController<FastrelayRealtimeEvent> controller;
}

class _WebSocketClientAdapter implements FastrelayRealtimeSocket {
  _WebSocketClientAdapter(Uri uri) : _socket = ws.WebSocket(uri) {
    connection = _socket.connection
        .map(_mapConnectionState)
        .where((state) => state != null)
        .cast<FastrelayRealtimeSocketState>();

    messages = _socket.messages
        .where((message) => message is String)
        .map((message) => message as String);
  }

  final ws.WebSocket _socket;

  @override
  late final Stream<FastrelayRealtimeSocketState> connection;

  @override
  late final Stream<String> messages;

  @override
  void close() {
    _socket.close();
  }

  @override
  void send(String message) {
    _socket.send(message);
  }

  static FastrelayRealtimeSocketState? _mapConnectionState(
    ws.ConnectionState state,
  ) {
    if (state is ws.Connecting) {
      return const FastrelayRealtimeSocketState(
        status: FastrelayRealtimeSocketStatus.connecting,
      );
    }

    if (state is ws.Connected) {
      return const FastrelayRealtimeSocketState(
        status: FastrelayRealtimeSocketStatus.connected,
      );
    }

    if (state is ws.Reconnecting || state is ws.Reconnected) {
      return const FastrelayRealtimeSocketState(
        status: FastrelayRealtimeSocketStatus.reconnecting,
      );
    }

    if (state is ws.Disconnected) {
      final dynamic disconnected = state;
      final Object? code = disconnected.code;
      return FastrelayRealtimeSocketState(
        status: FastrelayRealtimeSocketStatus.disconnected,
        closeCode: code is int ? code : int.tryParse('$code'),
        reason: disconnected.reason?.toString(),
        error: disconnected.error,
      );
    }

    if (state is ws.Disconnecting) {
      return const FastrelayRealtimeSocketState(
        status: FastrelayRealtimeSocketStatus.reconnecting,
      );
    }

    return null;
  }
}

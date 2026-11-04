class FastRelayConnectionEstablished {
  const FastRelayConnectionEstablished({
    required this.connectionId,
    required this.serverTime,
    required this.isReconnect,
  });

  final String connectionId;
  final DateTime? serverTime;
  final bool isReconnect;
}

import 'dart:async';

import 'package:nyxx/nyxx.dart';
import 'package:nyxx_lavalink/nyxx_lavalink.dart';

final _log = Logger('jana');
final _playingGuilds = <Snowflake>{};

Future<void> playInMemberVc(
    PartialMember member, PartialGuild guild, List<String> sources) async {
  final voiceChannel = guild.voiceStates[member.id]?.channel;
  if (voiceChannel == null) throw 'Join a voice channel first';
  if (!_playingGuilds.add(guild.id)) {
    throw 'Already playing audio in this server';
  }
  try {
    final vc = await voiceChannel.fetch() as VoiceChannel;
    _log.info(
        '[voice] connecting to channel ${vc.id} for ${sources.length} track(s)');
    final player = await vc.connectLavalink().timeout(Duration(seconds: 30));
    Duration? position;
    final events = StreamIterator(player.plugin.onMessage.where((event) {
      if (event.client != player.lavalinkClient) return false;
      if (event is PlayerUpdateMessage) {
        if (event.guildId != guild.id.toString()) return false;
        final state = event.state;
        if (!state.isConnected) return false;
        final progressing = position != state.position;
        position = state.position;
        return progressing;
      }
      if (event is! LavalinkEvent || event.guildId != guild.id.toString()) {
        return false;
      }
      if (event is TrackExceptionEvent) {
        final exception = event.exception;
        Error.throwWithStackTrace(
            exception.message ?? exception.cause,
            exception.causeStackTrace.isEmpty
                ? StackTrace.current
                : StackTrace.fromString(exception.causeStackTrace));
      }
      if (event is TrackStuckEvent || event is WebSocketClosedEvent) {
        throw StateError('Voice playback interrupted');
      }
      if (event is TrackEndEvent) {
        _log.fine('[voice] track ended: ${event.reason}');
        if (event.reason == 'loadFailed') {
          throw StateError('Track failed to load');
        }
        return true;
      }
      return false;
    }).timeout(Duration(seconds: 30)));

    Future<void> waitForEnd() async {
      while (await events.moveNext()) {
        if (events.current is TrackEndEvent) return;
      }
      throw StateError('Player updates stopped');
    }

    try {
      for (var i = 0; i < sources.length; i++) {
        position = null;
        final end = waitForEnd();
        _log.fine('[voice] starting track ${i + 1}/${sources.length}');
        await Future.wait([
          player.playIdentifier(sources[i]).timeout(Duration(seconds: 30)),
          end,
        ], eagerError: true);
      }
      await Future.delayed(Duration(milliseconds: 100));
    } finally {
      await events.cancel();
      try {
        await player.disconnect();
        _log.fine('[voice] disconnected from channel ${vc.id}');
      } catch (e, st) {
        _log.warning('[voice] disconnect failed', e, st);
      }
    }
  } finally {
    _playingGuilds.remove(guild.id);
  }
}

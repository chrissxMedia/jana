import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:mutex/mutex.dart';
import 'package:nyxx/nyxx.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final log = Logger('jana');

final internalId = Snowflake('826983242493591592');
final newsId = Snowflake('551908144641605642');
final yt = YoutubeExplode();

Stream<Video> getVideos() => yt.channels.getUploads('UCZs3FO5nPvK9VveqJLIvv_w');

void main(List<String> argv) async {
  final bot = NyxxFactory.createNyxxWebsocket(
      argv.first, GatewayIntents.allUnprivileged)
    ..registerPlugin(Logging())
    ..registerPlugin(CliIntegration());
  await bot.connect();

  final internal = await bot.fetchChannel(internalId) as ITextChannel;

  var logMutex = Mutex();
  IMessage? lastLog;
  var lastLogMsg = '';
  var lastLogCount = 1;
  Logger.root.onRecord.listen((rec) => logMutex.protect(() async {
        if (bot.ready) {
          final msg = '[${rec.level.name}] [${rec.loggerName}] ${rec.message}';
          if (lastLogMsg == msg) {
            lastLog?.edit(MessageBuilder.content('$msg x${++lastLogCount}'));
          } else {
            lastLog = await internal.sendMessage(MessageBuilder.content(msg));
            lastLogCount = 1;
            lastLogMsg = msg;
          }
        }
      }));

  bot.eventsWs.onMessageReceived.listen((event) async {
    final msg = event.message;
    final channel = await msg.channel.getOrDownload();
    if (msg.author.bot) return;
    log.info('Msg from ${msg.author.str()}: ${msg.content} (${msg.url})');
    if (msg.content == '!ping') {
      await channel.sendMessage(MessageBuilder.content('Pong!'));
    } else if (msg.content == '!test') {
      await yt.channels
          .getUploads('UCZs3FO5nPvK9VveqJLIvv_w')
          .map((v) => '${v.title},${v.url}')
          .reduce((a, b) => '$a\n$b')
          .then(utf8.encode)
          .then((v) => [AttachmentBuilder.bytes(v, 'vids.csv')])
          .then(MessageBuilder.files)
          .then(channel.sendMessage);
    }
  });

  checkYoutube(bot, await getVideos().map((v) => v.id.value).toList());
}

void checkYoutube(INyxxWebsocket bot, List<String> sent) async {
  log.info('Searching for new videos/streams...');
  final vids =
      await getVideos().where((v) => !sent.contains(v.id.value)).toList();
  if (vids.isNotEmpty) {
    // TODO: log what happens here
    final message = vids
        .map((v) => v.description
            .replaceAll('\r', '')
            .split('\n')
            .where((s) => s.startsWith('janamsg: '))
            .map((s) => s.replaceFirst('janamsg: ', '')))
        .fold<Iterable<String>>([], (a, b) => [...a, ...b])
        .fold<String>('', (a, b) => '$a\n$b');
    final reactions = vids
        .map((v) => v.description
            .replaceAll('\r', '')
            .split('\n')
            .where((s) => s.startsWith('janareact: '))
            .map((s) => s.replaceFirst('janareact: ', '')))
        .fold<Iterable<String>>([], (a, b) => [...a, ...b]);
    final ids = vids.map((v) => v.id.value).toList();
    final links =
        ids.map((x) => 'https://youtu.be/$x').reduce((p, e) => '$p $e');
    final msg = await bot.fetchChannel<ITextChannel>(newsId).then((chan) =>
        chan.sendMessage(MessageBuilder.content('@everyone$message\n$links')));
    await Future.wait(reactions.map(UnicodeEmoji.new).map(msg.createReaction));
    sent.addAll(ids);
  }
  Future.delayed(Duration(minutes: 5), () => checkYoutube(bot, sent));
}

extension Str on IMessageAuthor {
  String str() => '$username#$discriminator';
}

import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:nyxx/nyxx.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final log = Logger('jana');

final internal = Snowflake('826983242493591592');
final news = Snowflake('551908144641605642');
final yt = YoutubeExplode();

Stream<Video> getVideos() => yt.channels.getUploads('UCZs3FO5nPvK9VveqJLIvv_w');

void main(List<String> argv) async {
  final bot = NyxxFactory.createNyxxWebsocket(
      argv.first, GatewayIntents.allUnprivileged)
    ..registerPlugin(Logging())
    ..registerPlugin(CliIntegration());

  bot.eventsWs.onMessageReceived.listen((event) async {
    final msg = event.message;
    final channel = await msg.channel.getOrDownload();
    print('Msg from ${msg.author.str()}: ${msg.content} (${msg.url})');
    await bot.fetchChannel(internal).then((c) => c as ITextChannel).then((c) =>
        c.sendMessage(MessageBuilder.files([
          AttachmentBuilder.bytes(utf8.encode(msg.toString()), 'fux.txt')
        ])));
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

  await bot.connect();

  checkYoutube(bot, await getVideos().map((v) => v.id.value).toList());
}

void checkYoutube(INyxxWebsocket bot, List<String> sent) async {
  log.info('Searching for new videos/streams...');
  final vids =
      await getVideos().where((v) => !sent.contains(v.id.value)).toList();
  if (vids.isNotEmpty) {
    final cbt = vids.length == 2 &&
        vids.map((v) => v.title.toLowerCase()).fold<bool>(
            true, (p, v) => p && v.contains('cbt') && v.contains('vs'));
    final message = cbt
        ? 'Ihr könnt durch Reaktionen mit ⬅️ und ➡️ und Likes/Dislikes auf die Videos für das Uservoting abstimmen.'
        : vids
            .map((v) => v.description
                .replaceAll('\r', '')
                .split('\n')
                .where((s) => s.startsWith('janamsg: '))
                .map((s) => s.replaceFirst('janamsg: ', '')))
            .reduce((a, b) => [...a, ...b])
            .reduce((a, b) => '$a\n$b');
    final reactions = cbt
        ? ['⬅️', '➡️']
        : vids
            .map((v) => v.description
                .replaceAll('\r', '')
                .split('\n')
                .where((s) => s.startsWith('janareact: '))
                .map((s) => s.replaceFirst('janareact: ', '')))
            .reduce((a, b) => [...a, ...b]);
    final ids = vids.map((v) => v.id.value).toList();
    final links =
        ids.map((x) => 'https://youtu.be/$x').reduce((p, e) => '$p $e');
    final msg = await bot.fetchChannel<ITextChannel>(news).then((chan) => chan
        .sendMessage(MessageBuilder.content('@everyone\n$message\n$links')));
    await Future.wait(
        // can't we just get the dart people to make using normal constructors as functions possible
        reactions.map((x) => UnicodeEmoji(x)).map(msg.createReaction));
    sent.addAll(ids);
  }
  log.info('Done searching.');
  Future.delayed(Duration(minutes: 5), () => checkYoutube(bot, sent));
}

extension Str on IMessageAuthor {
  String str() => '$username#$discriminator';
}

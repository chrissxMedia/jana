import 'dart:convert';

import 'package:nyxx/nyxx.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final news = Snowflake('826983242493591592');

void main(List<String> argv) {
  final bot = NyxxFactory.createNyxxWebsocket(
      argv.first, GatewayIntents.allUnprivileged)
    ..registerPlugin(Logging())
    ..registerPlugin(CliIntegration())
    ..connect();
  final yt = YoutubeExplode();

  bot.eventsWs.onMessageReceived.listen((event) async {
    final msg = event.message;
    final channel = await msg.channel.getOrDownload();
    print('Msg from ${msg.author.str()}: ${msg.content} (${msg.url})');
    if (event.message.content == '!ping') {
      await channel.sendMessage(MessageBuilder.content('Pong!'));
    } else if (event.message.content == '!test') {
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

  checkYoutube(bot, yt, DateTime.now(), []);
}

void checkYoutube(INyxxWebsocket bot, YoutubeExplode yt, DateTime start,
        List<String> sent) async =>
    yt.channels
        .getUploads('UCZs3FO5nPvK9VveqJLIvv_w')
        .asyncMap((v) => yt.videos.get(v.id))
        .where((v) => v.publishDate?.isAfter(start) ?? false)
        .map((v) => v.id.value)
        .where((v) => !sent.contains(v))
        .forEach((stream) async {
      final channel = await bot.fetchChannel<ITextChannel>(news);
      await channel.sendMessage(
          MessageBuilder.content('@everyone https://youtu.be/$stream'));
      sent.add(stream);
    }).then((_) => Future.delayed(
            Duration(minutes: 5), () => checkYoutube(bot, yt, start, sent)));

extension Str on IMessageAuthor {
  String str() => '$username#$discriminator';
}

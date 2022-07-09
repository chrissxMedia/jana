import 'dart:convert';

import 'package:nyxx/nyxx.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void log(Object? msg) => print('[${DateTime.now()}] $msg');

final internal = Snowflake('826983242493591592');
final news = Snowflake('551908144641605642');
final yt = YoutubeExplode();

Stream<String> getVideoIds() =>
    yt.channels.getUploads('UCZs3FO5nPvK9VveqJLIvv_w').map((v) => v.id.value);

void main(List<String> argv) async {
  final bot = NyxxFactory.createNyxxWebsocket(
      argv.first, GatewayIntents.allUnprivileged)
    ..registerPlugin(Logging())
    ..registerPlugin(CliIntegration());

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

  await bot.connect();

  checkYoutube(bot, await getVideoIds().toList());
}

void checkYoutube(INyxxWebsocket bot, List<String> sent) async {
  log('Searching for new videos/streams...');
  await getVideoIds().where((v) => !sent.contains(v)).forEach((vid) async {
    final channel = await bot.fetchChannel<ITextChannel>(news);
    await channel
        .sendMessage(MessageBuilder.content('@everyone https://youtu.be/$vid'));
    sent.add(vid);
  });
  log('Done searching.');
  Future.delayed(Duration(minutes: 5), () => checkYoutube(bot, sent));
}

extension Str on IMessageAuthor {
  String str() => '$username#$discriminator';
}

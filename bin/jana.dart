import 'dart:convert';
import 'dart:developer';

import 'package:nyxx/nyxx.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main(List<String> argv) {
  final bot = Nyxx(argv.first, GatewayIntents.allUnprivileged,
      options: ClientOptions(guildSubscriptions: false));
  final yt = YoutubeExplode();

  bot.onMessageReceived.listen((event) async {
    final msg = event.message;
    final channel = await msg.channel.getOrDownload();
    print('Msg from ${str(msg.author)}: ${msg.content} (${msg.url})');
    if (event.message.content == '!ping') {
      await channel.sendMessage(content: 'Pong!');
    }
  });

  checkYoutube(bot, yt);
}

void checkYoutube(Nyxx bot, YoutubeExplode yt) async {
  final videos =
      yt.channels.getUploads('UCZs3FO5nPvK9VveqJLIvv_w').where((v) => v.isLive);
  final channel =
      await bot.fetchChannel<TextChannel>(Snowflake('826983242493591592'));
  await channel.sendMessage(files: [
    AttachmentBuilder.bytes(
        utf8.encode(jsonEncode(await videos.map((v) => v.toString()).toList())),
        'kek.json')
  ]);
  Future.delayed(Duration(minutes: 10), () => checkYoutube(bot, yt));
}

String str(IMessageAuthor author) =>
    '${author.username}#${author.discriminator}';

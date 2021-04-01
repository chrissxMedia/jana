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

  checkYoutube(bot, yt, []);
}

void checkYoutube(Nyxx bot, YoutubeExplode yt, List<String> sent) async {
  final streams =
      yt.channels.getUploads('UCZs3FO5nPvK9VveqJLIvv_w').where((v) => v.isLive);
  if (!(await streams.isEmpty)) {
    final stream = (await streams.first).id.value;
    if (!sent.contains(stream)) {
      final channel =
          await bot.fetchChannel<TextChannel>(Snowflake('826983242493591592'));
      await channel.sendMessage(content: '@everyone https://youtu.be/$stream');
      sent.add(stream);
    }
  }
  Future.delayed(Duration(minutes: 10), () => checkYoutube(bot, yt, sent));
}

String str(IMessageAuthor author) =>
    '${author.username}#${author.discriminator}';

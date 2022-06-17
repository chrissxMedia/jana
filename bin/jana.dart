import 'dart:convert';
import 'dart:io';

import 'package:nyxx/nyxx.dart';
import 'package:stash/stash_api.dart';
import 'package:stash_file/stash_file.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void log(Object? msg) => print('[${DateTime.now()}] $msg');

final news = Snowflake('826983242493591592');
late final Cache<Map> cache;
final yt = YoutubeExplode();

Future<Map> getVideo(String id) async {
  final cached = await cache.get(id);
  if (cached != null) return cached;
  log('Cache miss for $id');
  final r = await yt.videos.get(id);
  final vid = {
    'url': r.url,
    'author': r.author,
    'channelId': r.channelId.value,
    'description': r.description,
    'duration': r.duration?.toString(),
    'likes': r.engagement.likeCount,
    'dislikes': r.engagement.dislikeCount,
    'rating': r.engagement.avgRating,
    'id': r.id.value,
    'isLive': r.isLive,
    'keywords': r.keywords,
    'publishDate': r.publishDate?.toIso8601String(),
    'thumbnailMax': r.thumbnails.maxResUrl,
    'title': r.title,
    'uploadDate': r.uploadDate?.toIso8601String(),
  };
  await cache.put(id, vid);
  return vid;
}

void main(List<String> argv) async {
  cache = await Directory('/var/cache')
      .create()
      .then((_) => newFileLocalCacheStore(path: '/var/cache/jana'))
      .then((store) => store.cache<Map>(name: 'yt_vids'));

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

  checkYoutube(bot, DateTime.now(), []);
}

void checkYoutube(INyxxWebsocket bot, DateTime start, List<String> sent) async {
  log('Searching for new videos/streams...');
  await yt.channels
      .getUploads('UCZs3FO5nPvK9VveqJLIvv_w')
      .asyncMap((v) => getVideo(v.id.value))
      .where(
          (v) => DateTime.tryParse(v['publishDate'])?.isAfter(start) ?? false)
      .map((v) => v['id'])
      .where((v) => !sent.contains(v))
      .forEach((stream) async {
    final channel = await bot.fetchChannel<ITextChannel>(news);
    await channel.sendMessage(
        MessageBuilder.content('@everyone https://youtu.be/$stream'));
    sent.add(stream);
  });
  log('Done searching.');
  Future.delayed(Duration(minutes: 5), () => checkYoutube(bot, start, sent));
}

extension Str on IMessageAuthor {
  String str() => '$username#$discriminator';
}

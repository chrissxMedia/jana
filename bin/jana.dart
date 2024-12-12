import 'dart:convert';
import 'dart:io';

import 'package:mutex/mutex.dart';
import 'package:nyxx/nyxx.dart';
import 'package:nyxx_extensions/nyxx_extensions.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:youtube_poll/youtube_poll.dart';

final log = Logger('jana');

final internalId = Snowflake(826983242493591592);
late final TextChannel internal;
final newsId = Snowflake(551908144641605642);
late final TextChannel news;
final yt = YoutubePoll();
final startupTime = DateTime.now().subtract(Duration(days: 1));
const ytChannels = <(String, bool)>[
  ("UCZs3FO5nPvK9VveqJLIvv_w", true), // main
  ("UCF7z3rssaZjx7SxJ0IqSNvw", false), // xxlp
  ("UC20oDKphj67NRDwKKy3JC_A", false), // pixeleng
  ("UCMawD8L365TRdcqhQiTDLKA", false), // twinkspotting (→ other dc channel)
];

Map videoToJson(Video v) => {
      'author': v.author,
      'channelId': v.channelId.value,
      'description': v.description,
      'duration': v.duration?.inSeconds,
      'hasWatchPage': v.hasWatchPage,
      'id': v.id.value,
      'isLive': v.isLive,
      'publishDate': v.publishDate?.toIso8601String(),
      'title': v.title,
      'uploadDate': v.uploadDate?.toIso8601String(),
      'uploadDateRaw': v.uploadDateRaw,
      'url': v.url,
    }..removeWhere((key, value) => value == null);

extension SendJson on TextChannel {
  Future sendJson(String json, [String fileName = "message.json"]) {
    if (json.length < 1984) {
      return sendMessage(MessageBuilder(content: '```json\n$json\n```'));
    } else {
      return sendMessage(MessageBuilder(attachments: [
        AttachmentBuilder(fileName: fileName, data: utf8.encode(json))
      ]));
    }
  }
}

void main(List<String> argv) async {
  final token = Platform.environment['JANA_DISCORD_TOKEN'] ?? argv.firstOrNull;
  if (token == null || token.isEmpty) {
    stderr.writeln('No token provided (env JANA_DISCORD_TOKEN or pass as arg)');
    exit(1);
  }

  final bot = await Nyxx.connectGateway(
      token, GatewayIntents.allUnprivileged | GatewayIntents.messageContent,
      options: GatewayClientOptions(plugins: [Logging(), CliIntegration()]));

  internal = await bot.channels.get(internalId) as TextChannel;
  news = await bot.channels.get(newsId) as TextChannel;

  final logMutex = Mutex();
  Message? lastLog;
  var lastLogMsg = '';
  var lastLogCount = 1;
  Logger.root.onRecord.listen((rec) => logMutex.protect(() async {
        final ping = rec.level >= Level.WARNING ? ' <@231670489779666944>' : '';
        var msg = '[${rec.level.name}] [${rec.loggerName}] ${rec.message}$ping';
        if (rec.error != null) msg += '\nError: ${rec.error}';
        if (rec.stackTrace != null) {
          msg += '\nStack trace:\n```${rec.stackTrace}```';
        }
        if (lastLogMsg == msg) {
          lastLog
              ?.edit(MessageUpdateBuilder(content: '$msg x${++lastLogCount}'));
        } else {
          lastLog = await internal.sendMessage(MessageBuilder(content: msg));
          lastLogCount = 1;
          lastLogMsg = msg;
        }
      }));

  bot.onMessageCreate.listen((event) async {
    final msg = event.message;
    final channel = await msg.channel.get() as TextChannel;
    if (msg.author is WebhookAuthor || (msg.author as User).isBot) return;
    log.info(
        'Msg from ${msg.author.username}: ${msg.content} (${await msg.url})');
    if (msg.content == '!ping') {
      await channel.sendMessage(MessageBuilder(content: 'Pong!'));
    } else if (msg.content.startsWith('!vid')) {
      final ids = msg.content.split(' ')..removeAt(0);
      for (final id in ids) {
        try {
          await yt.yt.videos.get(id).then(
              (v) => channel.sendJson(json.encode(videoToJson(v)), '$id.json'));
        } catch (e, st) {
          log.warning('!vid error', e, st);
          await channel.sendMessage(MessageBuilder(content: e.toString()));
        }
      }
    }
  });

  for (final (id, notify) in ytChannels) {
    await yt.ignoreOld(id);
    yt.pollBatched(id).listen((vids) => handleNewVideos(bot, notify, vids));
  }
}

Future<void> handleNewVideos(
    NyxxGateway bot, bool notify, List<Video> vids) async {
  log.info('[yt] new videos: $vids');
  try {
    // TODO: consider putting the message before the video it belongs to
    final messages = <String>[];
    final reactions = <String>[];
    final links = <String>[];
    final ids = <String>[];
    for (final vid in vids) {
      log.info('[yt] processing video', vid.url);
      internal.sendJson(json.encode(videoToJson(vid)), 'vid.json');
      ids.add(vid.id.value);

      if ((vid.publishDate ?? vid.uploadDate ?? DateTime.now())
          .isBefore(startupTime)) {
        log.warning('[yt] is an old video');
        continue;
      }

      Iterable<String> lines(String separator) => vid.description
          .replaceAll('\r', '')
          .split('\n')
          .where((s) => s.startsWith(separator))
          .map((s) => s.replaceFirst(separator, ''));
      messages.addAll(lines('janamsg: '));
      reactions.addAll(lines('janareact: '));
      links.add('https://youtu.be/${vid.id.value}');
      log.info('[yt] added');
    }
    if (links.isNotEmpty) {
      log.info('[yt] building and sending message');
      final message =
          messages.isEmpty ? '' : messages.reduce((a, b) => '$a\n$b');
      final link = links.reduce((p, e) => '$p $e');
      final tag = notify ? '@everyone ' : '';
      final msg = await news
          .sendMessage(MessageBuilder(content: '$tag$message\n$link'));
      await Future.wait(reactions
          .map(bot.getTextEmoji)
          .map(ReactionBuilder.fromEmoji)
          .map(msg.react));
      log.info('[yt] all done');
    }
  } catch (e, st) {
    log.severe('[yt] update error', e, st);
  }
}

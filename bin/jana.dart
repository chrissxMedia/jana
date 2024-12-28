import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mutex/mutex.dart';
import 'package:nyxx/nyxx.dart';
import 'package:nyxx_extensions/nyxx_extensions.dart';
import 'package:nyxx_lavalink/nyxx_lavalink.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:youtube_poll/youtube_poll.dart';

final log = Logger('jana');

const internal = Snowflake(826983242493591592);
const news = Snowflake(551908144641605642);
const twinkspotting = Snowflake(1292515671439315027);
const priv = [Snowflake(1310347280406151168), Snowflake(1285544156185366559)];
const admins = Snowflake(569251424370819088);
final yt = YoutubePoll();
final startupTime = DateTime.now().subtract(Duration(days: 1));
const ytChannels = <(String, bool, Snowflake)>[
  ("UCZs3FO5nPvK9VveqJLIvv_w", true, news), // main
  ("UCF7z3rssaZjx7SxJ0IqSNvw", false, news), // xxlp
  ("UC20oDKphj67NRDwKKy3JC_A", false, news), // pixeleng
  ("UCMawD8L365TRdcqhQiTDLKA", false, twinkspotting), // twinkspotting
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
  final env = Platform.environment;
  final token = env['JANA_DISCORD_TOKEN']?.isNotEmpty ?? false
      ? env['JANA_DISCORD_TOKEN']
      : argv.firstOrNull;
  if (token == null || token.isEmpty) {
    stderr.writeln('No token provided (env JANA_DISCORD_TOKEN or pass as arg)');
    exit(1);
  }

  final lavalink = (env['JANA_LAVALINK_BASE']?.isNotEmpty ?? false) &&
          (env['JANA_LAVALINK_PASSWORD']?.isNotEmpty ?? false)
      ? LavalinkPlugin(
          base: Uri.parse(env['JANA_LAVALINK_BASE']!),
          password: env['JANA_LAVALINK_PASSWORD']!,
        )
      : null;

  final bot = await Nyxx.connectGateway(
      token, GatewayIntents.allUnprivileged | GatewayIntents.messageContent,
      options: GatewayClientOptions(
          plugins: [logging, cliIntegration, if (lavalink != null) lavalink]));

  final logMutex = Mutex();
  Message? lastLog;
  var lastLogMsg = '';
  var lastLogCount = 1;
  Logger.root.onRecord.listen((rec) => logMutex.protect(() async {
        // TODO: if > 3900 dont send?
        final ping = rec.level >= Level.WARNING ? ' <@&$admins>' : '';
        var msg = '[${rec.level.name}] [${rec.loggerName}] ${rec.message}$ping';
        if (rec.error != null) msg += '\nError: ${rec.error}';
        if (rec.stackTrace != null) {
          msg += '\nStack trace:\n```${rec.stackTrace}```';
        }
        if (lastLogMsg == msg) {
          lastLog
              ?.edit(MessageUpdateBuilder(content: '$msg x${++lastLogCount}'));
        } else {
          lastLog = await (await bot.channels.get(internal) as TextChannel)
              .sendMessage(MessageBuilder(content: msg));
          lastLogCount = 1;
          lastLogMsg = msg;
        }
      }));

  bot.onMessageCreate.listen((event) async {
    final msg = event.message;

    if (!msg.content.startsWith('!') ||
        event.member == null ||
        msg.author is WebhookAuthor ||
        (msg.author as User).isBot) {
      return;
    }

    final member = await event.member!.get();
    final channel = await msg.channel.get() as TextChannel;
    final args = msg.content.split(' ');
    final cmd = args.removeAt(0).toLowerCase();

    final commands = <String, FutureOr<dynamic> Function()>{
      '!ping': () => channel.sendMessage(MessageBuilder(content: 'Pong!')),
      '!vid': () async {
        for (final id in args) {
          await yt.yt.videos.get(id).then(
              (v) => channel.sendJson(json.encode(videoToJson(v)), '$id.json'));
        }
      },
      if (lavalink != null)
        '!play': () async {
          if (!member.roleIds.any(priv.contains)) throw 'Not authorized';
          final sources = ['https://gock.dev/email_empfangen.flac'];
          if (member.roleIds.contains(admins)) {
            sources.addAll(msg.attachments
                .where((a) => a.url.path.endsWith('.mp3'))
                .map((a) => a.url.toString()));
            sources.addAll(args);
          }
          final voice = event.guild!.voiceStates[member.id]!;
          final vc = await voice.channel!.fetch() as VoiceChannel;
          final player = await vc.connectLavalink();
          await player.playIdentifier(sources.removeAt(0));
          player.onTrackEnd.listen((_) => sources.isNotEmpty
              ? player.playIdentifier(sources.removeAt(0))
              : player.disconnect());
        },
    };

    final handler = commands[cmd];
    if (handler != null) {
      try {
        await handler();
      } catch (e, st) {
        log.warning('$cmd error', e, st);
        await channel.sendMessage(MessageBuilder(content: e.toString()));
      }
    }
  });

  if (lavalink == null) {
    log.warning('No Lavalink configured');
  }

  Duration interval() {
    final target = DateTime(2000, 1, 1, 1, 0, 45);
    final now = DateTime.now().copyWith(year: 2000, month: 1, day: 1, hour: 0);
    final diff = target.difference(now);
    if (diff < Duration(minutes: 1)) return Duration(minutes: 1);
    if (diff > Duration(minutes: 30)) return Duration(minutes: 30);
    return diff;
  }

  for (final (id, not, dChan) in ytChannels) {
    await yt.ignoreOld(id);
    void handle(List<Video> vids) => handleNewVideos(bot, not, dChan, vids);
    yt.pollBatched(id, interval).listen(handle);
  }
}

Future<void> handleNewVideos(
    NyxxGateway bot, bool notify, Snowflake dcChannel, List<Video> vids) async {
  log.info('[yt] new videos: $vids');
  try {
    // TODO: consider putting the message before the video it belongs to
    final messages = <String>[];
    final reactions = <String>[];
    final links = <String>[];
    final ids = <String>[];
    for (final vid in vids) {
      log.info('[yt] processing video', vid.url);
      (await bot.channels.get(internal) as TextChannel)
          .sendJson(json.encode(videoToJson(vid)), 'vid.json');
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
      final msg = await (await bot.channels.get(dcChannel) as TextChannel)
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

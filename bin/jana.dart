import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mutex/mutex.dart';
import 'package:nyxx/nyxx.dart';
import 'package:nyxx_extensions/nyxx_extensions.dart';
import 'package:nyxx_lavalink/nyxx_lavalink.dart';
import 'package:prometheus_client/runtime_metrics.dart' as runtime_metrics;
import 'package:prometheus_client_shelf/shelf_handler.dart';
import 'package:shelf/shelf_io.dart';
import 'package:webfeed_revised/webfeed_revised.dart';
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
  ("UC20oDKphj67NRDwKKy3JC_A", true, news), // pixeleng
  ("UCMawD8L365TRdcqhQiTDLKA", false, twinkspotting), // twinkspotting
];

const rssFeeds = <String>[
  "https://zerm.eu/rss.xml",
  "https://gock.dev/blog/rss.xml",
  "https://chrissx.de/notices/rss.xml",
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

  runtime_metrics.register();
  serve(prometheusHandler(), InternetAddress.anyIPv6, 8988).then((s) => log
      .info('Serving metrics at http://${s.address.host}:${s.port}/metrics'));

  final logMutex = Mutex();
  Message? lastLog;
  var lastLogMsg = '';
  var lastLogCount = 1;
  Logger.root.level = Level.FINE;
  Logger.root.onRecord.listen((rec) => logMutex.protect(() async {
        if (rec.level <= Level.INFO) return;
        if (rec.loggerName.contains("Nyxx.") &&
            rec.message.contains("rate limiting")) return;
        final ping = rec.level >= Level.WARNING ? ' <@&$admins>' : '';
        var msg = '[${rec.level.name}] [${rec.loggerName}] ${rec.message}$ping';
        if (rec.error != null) {
          msg += '\nError: ${rec.error}';
        }
        if (rec.stackTrace != null) {
          msg += '\nStack trace:\n```${rec.stackTrace}```';
        }
        if (msg.length > 1950) {
          msg = '${msg.substring(0, 1950)} ... (see logs for full message)';
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

  bot.onReady.listen((_) => log.info('jana v2 is ready'));

  bot.onMessageCreate.listen((event) async {
    final msg = event.message;
    log.fine('${msg.author.username}: $msg');

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

    final commands = <String, (String, FutureOr<dynamic> Function())>{
      '!ping': (
        'replies with Pong! (everyone)',
        () => channel.sendMessage(MessageBuilder(content: 'Pong!'))
      ),
      '!vid': (
        '<id...> - dumps video info as JSON (everyone)',
        () async {
          for (final id in args) {
            await yt.yt.videos.get(id).then(
                (v) => channel.sendJson(json.encode(videoToJson(v)), '$id.json'));
          }
        }
      ),
      '!meow': (
        'says Meow! (requires priv role)',
        () {
          if (!member.roleIds.any(priv.contains)) throw 'Not authorized';
          log.info(Iterable.generate(4 * 420).map((_) => 'meow').join(' '));
          channel.sendMessage(MessageBuilder(content: 'Meow!'));
        }
      ),
      '!stop': (
        'shuts down the bot (requires admins role)',
        () async {
          if (!member.roleIds.contains(admins)) throw 'Not authorized';
          await msg.url.then((x) => 'shut down requested: $x').then(log.info);
          exit(0);
        }
      ),
      if (lavalink != null)
        '!play': (
          '[url...] - plays audio in your voice channel (requires priv role)',
          () async {
            if (!member.roleIds.any(priv.contains)) throw 'Not authorized';
            final sources = ['https://gock.dev/email_empfangen.flac'];
            if (member.roleIds.contains(admins)) {
              sources.addAll(msg.attachments.map((a) => a.url.toString()));
              sources.addAll(args);
            }
            final player = await joinMemberVc(member, event.guild!, channel);
            await player.playIdentifier(sources.removeAt(0));
            player.onTrackEnd.listen((_) => sources.isNotEmpty
                ? player.playIdentifier(sources.removeAt(0))
                : player.disconnect());
          }
        ),
      if (lavalink != null)
        '!speak': (
          '<text> - speaks text in your voice channel (requires priv role)',
          () async {
            if (!member.roleIds.any(priv.contains)) throw 'Not authorized';
            final player = await joinMemberVc(member, event.guild!, channel);
            await player.playIdentifier('speak:${args.join(' ')}');
            player.onTrackEnd.listen((_) => Future.delayed(
                Duration(milliseconds: 100), () => player.disconnect()));
          }
        ),
    };
    commands['!help'] = (
      'lists all commands (everyone)',
      () {
        final lines =
            commands.entries.map((e) => '${e.key} ${e.value.$1}').join('\n');
        return channel.sendMessage(MessageBuilder(content: lines));
      }
    );

    final handler = commands[cmd]?.$2;
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

  final ytMutex = Mutex();
  for (final (id, not, dChan) in ytChannels) {
    await yt.ignoreOld(id);
    void handle(List<Video> vids) =>
        ytMutex.protect(() => handleNewVideos(id, bot, not, dChan, vids));
    void er(Object e, StackTrace st) => log.severe('[yt] polling error', e, st);
    yt.pollBatched(id, ytPollInterval).listen(handle, onError: er);
  }

  final rssMutex = Mutex();
  for (final url in rssFeeds) {
    final seen = <String>{};
    var first = true;
    Future<void> poll() => rssMutex.protect(() async {
          await handleNewRssItems(url, bot, seen, seedOnly: first);
          first = false;
        });
    await poll();
    Timer.periodic(const Duration(minutes: 10), (_) => poll());
  }
}

Future<LavalinkPlayer> joinMemberVc(PartialMember member, PartialGuild guild,
    [TextChannel? channel]) async {
  final voice = guild.voiceStates[member.id]!;
  final vc = await voice.channel!.fetch() as VoiceChannel;
  final player = await vc.connectLavalink();
  player.onTrackException.listen((e) {
    log.warning('!play error', e);
    channel?.sendMessage(MessageBuilder(content: e.toString()));
    player.disconnect();
  });
  return player;
}

Duration ytPollInterval() {
  final target = DateTime(2020, 1, 1, 1, 0, 45);
  final now = DateTime.now().copyWith(year: 2020, month: 1, day: 1, hour: 0);
  final diff = target.difference(now);
  if (diff < Duration(minutes: 1)) return Duration(minutes: 1);
  if (diff > Duration(minutes: 30)) return Duration(minutes: 30);
  return diff;
}

Future<void> handleNewVideos(String id, NyxxGateway bot, bool notify,
    Snowflake dcChannel, List<Video> vids) async {
  log.info('[yt] new videos: $vids'); // TODO:
  log.fine('[yt] from $id for $dcChannel');
  if (vids.isEmpty) return;
  try {
    final blocks = <String>[];
    final reactions = <String>[];
    final channel = await bot.channels.get(dcChannel) as TextChannel;
    late final List<Message> history;
    try {
      history = await channel.messages.fetchMany(limit: 50);
    } catch (e, st) {
      log.warning('[yt] history fetch failed, posting anyway', e, st);
      history = [];
    }
    for (final vid in vids) {
      log.info('[yt] processing video', vid.url);
      (await bot.channels.get(internal) as TextChannel)
          .sendJson(json.encode(videoToJson(vid)), 'vid.json');

      if ((vid.publishDate ?? vid.uploadDate ?? DateTime.now())
          .isBefore(startupTime)) {
        log.warning('[yt] is an old video');
        continue;
      }

      if (history.any((m) => m.content.contains(vid.id.value))) {
        log.info('[yt] already posted, skipping ${vid.id.value}');
        continue;
      }

      Iterable<String> lines(String separator) => vid.description
          .replaceAll('\r', '\n')
          .split('\n')
          .where((s) => s.startsWith(separator))
          .map((s) => s.replaceFirst(separator, ''));
      final videoMessage = lines('janamsg: ').join('\n');
      reactions.addAll(lines('janareact: '));
      blocks.add('$videoMessage\nhttps://youtu.be/${vid.id.value}');
      log.info('[yt] added ${vid.id.value}');
    }
    if (blocks.isNotEmpty) {
      log.info('[yt] building and sending message');
      final tag = notify ? '@everyone ' : '';
      final msg = await channel
          .sendMessage(MessageBuilder(content: '$tag${blocks.join('\n')}'));
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

Future<List<(String id, String title, String link)>> fetchRssEntries(
    String url) async {
  final client = HttpClient();
  try {
    final req =
        await client.getUrl(Uri.parse(url)).timeout(Duration(seconds: 20));
    final res = await req.close().timeout(Duration(seconds: 20));
    if (res.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${res.statusCode} for $url');
    }
    final xml =
        await res.transform(utf8.decoder).join().timeout(Duration(seconds: 20));
    final feed = RssFeed.parse(xml);
    return [
      for (final item in feed.items ?? <RssItem>[])
        if ((item.link ?? '').isNotEmpty)
          (item.guid ?? item.link!, item.title ?? 'New post', item.link!),
    ];
  } finally {
    client.close();
  }
}

Future<void> handleNewRssItems(String url, NyxxGateway bot, Set<String> seen,
    {bool seedOnly = false}) async {
  try {
    final entries = await fetchRssEntries(url);
    final fresh = entries.where((e) => !seen.contains(e.$1)).toList();
    if (seedOnly) {
      seen.addAll(entries.map((e) => e.$1));
      log.info('[rss] seeded ${entries.length} items from $url');
      return;
    }
    if (fresh.isEmpty) return;
    final channel = await bot.channels.get(news) as TextChannel;
    late final List<Message> history;
    try {
      history = await channel.messages.fetchMany(limit: 50);
    } catch (e, st) {
      log.warning('[rss] history fetch failed, posting anyway', e, st);
      history = [];
    }
    for (final (id, title, link) in fresh) {
      log.info('[rss] new item: $title $link');
      if (history.any((m) =>
          m.content.contains(id) ||
          (link.isNotEmpty && m.content.contains(link)))) {
        log.info('[rss] already posted, skipping $id');
        continue;
      }
      await channel.sendMessage(MessageBuilder(content: '$title\n$link'));
    }
    seen.addAll(fresh.map((e) => e.$1));
  } catch (e, st) {
    log.warning('[rss] fetch/parse failed for $url', e, st);
  }
}

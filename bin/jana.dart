import 'dart:async';
import 'dart:io';

import 'package:jana/lavalink.dart';
import 'package:mutex/mutex.dart';
import 'package:nyxx/nyxx.dart';
import 'package:nyxx_extensions/nyxx_extensions.dart';
import 'package:nyxx_lavalink/nyxx_lavalink.dart';
import 'package:prometheus_client/runtime_metrics.dart' as runtime_metrics;
import 'package:prometheus_client_shelf/shelf_handler.dart';
import 'package:shelf/shelf_io.dart';

final log = Logger('jana');

const internal = Snowflake(826983242493591592);
const priv = [Snowflake(1310347280406151168), Snowflake(1285544156185366559)];
const admins = Snowflake(569251424370819088);

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
            rec.message.contains("rate limiting")) {
          return;
        }
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

  bot.onReady.listen((_) => log.info('jana v3 is ready'));

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
    final args = msg.content.split(RegExp(r'\s+'));
    final cmd = args.removeAt(0).toLowerCase();

    final commands = <String, (String, FutureOr<dynamic> Function())>{
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
          '[url...] - plays URLs or attached audio in your voice channel (requires priv role)',
          () async {
            if (!member.roleIds.any(priv.contains)) throw 'Not authorized';
            final sources = [
              ...msg.attachments.map((a) => a.url.toString()),
              ...args
                  .map((s) => s.replaceAll(RegExp(r'^<|>$'), ''))
                  .where((s) => s.isNotEmpty),
            ];
            if (sources.isEmpty) throw 'Provide a URL or attach an audio file';
            await playInMemberVc(member, event.guild!, sources);
          }
        ),
      if (lavalink != null)
        '!speak': (
          '<text> - speaks text in your voice channel (requires priv role)',
          () async {
            if (!member.roleIds.any(priv.contains)) throw 'Not authorized';
            final text = args.join(' ').trim();
            if (text.isEmpty) throw 'Provide text to speak';
            await playInMemberVc(member, event.guild!, ['speak:$text']);
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
}

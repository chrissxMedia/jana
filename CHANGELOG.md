## 1.5.1

- Ping the admin (pixel) by id, not name
- Don't fail if there is no custom message from any of the videos

## 1.5.0

- Added support for `JANA_DISCORD_TOKEN` environment variable instead of using args
- A lot of logging for the YT video posting
- YT videos are now processed synchronously
- The used channels are now just kept as globals

## 1.4.0

- `nyxx` 6
- Added `messageContent` intent
- Logging: send `error` and `stackTrace` if given
- Logging: ping the admin if the log level is >= warning
- Added/Adjusted `!vids` and `!vid` commands
- The first `checkYoutube` invocation is now also delayed
(to not cause any DOS issues, as unlikely as they already were)
- Catch errors in `checkYoutube` and the command processing and log them
(and tell the user in case of the commands)
- Fixed YouTube descriptions being empty (the channel page doesn't have them)
- `checkYoutube` now makes sure videos weren't published before IED'23
(which is a stopgap measure for stopping it from telling people about old videos
in certain edge cases, that have happened btw)

## 1.3.0

- `nyxx` 5, `dart` 3
- Removed CBT-specific code

## 1.2.2

- Fixed a crash when videos don't specify messages or reactions

## 1.2.1

- Add logging to the internal channel, in addition to stdout

## 1.2.0

- Added support for custom messages and reactions in the video descriptions

## 1.1.1

- Fixed bug that caused video IDs instead of video links to be posted

## 1.1.0

- CBT-specific handling to add some voting information
- `nyxx` 4.0.0

## 1.0.4

- Instead of posting each one separately, videos published at the same time are
  now in one message
- Logging integrates properly with `nyxx`

## 1.0.3

- New video narrowing algorithm with many advantages

## 1.0.2

- News are now posted into the proper channel

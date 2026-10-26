# jana

Discord audio bot for
[the official chrissx Media Server](https://chrissx.de/discord), with URL and
attachment playback and text-to-speech through Lavalink.

Version 3.0.0 removes `!ping`, `!meow`, `!vid`, and YouTube polling and
announcements. The RSS webhook handles announcements instead. YouTube URL
playback still depends on Lavalink's configured sources.

```sh
# Without Lavalink
docker run -d --restart=unless-stopped --pull=always -e JANA_DISCORD_TOKEN=XXX chrissx/jana:latest

# With Lavalink running on network lavalink as container lavalink
docker run -d --restart=unless-stopped --pull=always --network lavalink -e JANA_DISCORD_TOKEN=XXX -e JANA_LAVALINK_BASE=http://lavalink:2333 -e JANA_LAVALINK_PASSWORD=XXX chrissx/jana:latest

# Example Lavalink setup
docker run -d --name lavalink --restart=unless-stopped --pull=always --network lavalink -e SERVER_PORT=2333 -e LAVALINK_SERVER_PASSWORD=XXX -v$PWD/application.yml:/opt/Lavalink/application.yml ghcr.io/lavalink-devs/lavalink:4
```

## Commands

Run `!help` in Discord to list all commands. Output matches this table.

| Command          | Description                                        | Who      | Lavalink |
| ---------------- | -------------------------------------------------- | -------- | -------- |
| `!stop`          | shuts down the bot                                 | admins   | no       |
| `!play [url...]` | plays URLs or attached audio in your voice channel | priv     | yes      |
| `!speak <text>`  | speaks text in your voice channel                  | priv     | yes      |
| `!help`          | lists all commands                                 | everyone | no       |

`!play` and `!speak` only exist when Lavalink is configured.

Only one playback command can run per server at a time. Playback stops if
Lavalink reports a stalled track or lost voice connection, or if the playback
position stops changing for 30 seconds. Healthy tracks and streams have no
length limit.

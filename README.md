# jana

Discord bot for [the official chrissx Media Server](https://chrissx.de/discord).

```sh
# Without Lavalink
docker run -d --restart=unless-stopped --pull=always -e JANA_DISCORD_TOKEN=XXX chrissx/jana:latest

# With Lavalink running on Network lavalink on localhost:2333
docker run -d --restart=unless-stopped --pull=always --network lavalink -e JANA_DISCORD_TOKEN=XXX -e JANA_LAVALINK_BASE=http://localhost:2333 -e JANA_LAVALINK_PASSWORD=XXX chrissx/jana:latest

# Example Lavalink setup
docker run -d --restart=unless-stopped --pull=always --network lavalink -e SERVER_PORT=2333 -e LAVALINK_SERVER_PASSWORD=XXX -v$PWD/application.yml:/opt/Lavalink/application.yml ghcr.io/lavalink-devs/lavalink:4
```

## Commands

Run `!help` in Discord to list all commands. Output matches this table.

| Command          | Description                       | Who                                          | Lavalink |
| ---------------- | --------------------------------- | -------------------------------------------- | -------- |
| `!ping`          | replies with Pong!                | everyone                                     | no       |
| `!vid <id...>`   | dumps video info as JSON          | everyone                                     | no       |
| `!meow`          | says Meow!                        | priv                                         | no       |
| `!stop`          | shuts down the bot                | admins                                       | no       |
| `!play [url...]` | plays audio in your voice channel | priv (admins may also pass URLs/attachments) | yes      |
| `!speak <text>`  | speaks text in your voice channel | priv                                         | yes      |
| `!help`          | lists all commands                | everyone                                     | no       |

`!play` and `!speak` only exist when Lavalink is configured.

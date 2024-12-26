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

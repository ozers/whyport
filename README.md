# whyport

See why a port is open, where it is used, and close it. From the macOS menu bar.

Click the icon, or press **⌃⌥P** anywhere, and you get every port your projects are listening on: the project and git branch behind it, the Docker container that publishes it, how long it has been running, its memory, and whether anything is connected. Click a row for the full story, then stop or restart it with one button.

## What it does

- **Why it is open** - one sentence per port: which program, which project and branch, what launched it (`npm run dev`, `go run`, a Gradle task), localhost or the whole network, and who is connected
- **Where it is used** - live connections with the process on the other end
- **Stops the whole thing** - `npm run dev`, its shell and its server stop together, so nothing respawns. Terminals, editors, coding agents and shared build daemons are never part of the group
- **Restart** - stops the group and runs the same command again in the same folder. Output goes to `~/Library/Logs/WhyPort`
- **Force quit** - if a process ignores the stop request, a Force quit button appears
- **Network exposure** - ports bound to all interfaces get an orange badge and a filter, with the LAN address other devices would use and how to keep it local
- **Docker aware** - published ports show the container name and image; Stop and Restart run `docker stop` and `docker restart`
- **Bulk stop** - Select, then pick servers yourself or let **Select idle** find the ones with no connections, no CPU and more than 30 minutes of uptime
- **Memory and CPU charts** - ten minutes of history for the whole process group, with a memory limit that turns the menu bar icon orange
- **Notifications** - when a port becomes reachable from the network, when memory goes over the limit, and optionally when servers start or stop. Notifications have a Stop button
- **Pin and hide** - right-click a row to keep it on top or out of the list
- **Open in your tools** - Cursor, VS Code, IntelliJ, Zed and more; Terminal, iTerm, Ghostty, Warp or kitty
- **Projects or Everything** - build daemons, IDEs and system apps stay out of the way until you ask for them

Nothing leaves your Mac. The app reads `lsof`, `ps` and `docker ps`.

## Install

Download `WhyPort.dmg` from the latest release, open it, and drag WhyPort into Applications. The app is not notarized yet, so the first time, right-click WhyPort in Applications and choose **Open**.

With Homebrew, once the cask is published:

```bash
brew install --cask --no-quarantine whyport
```

### Build it yourself

macOS 14 or later with the Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/ozers/whyport.git
cd whyport/app
./build-app.sh --install
```

| Command | What it does |
| --- | --- |
| `./build-app.sh` | Build `app/.build/WhyPort.app` for this Mac |
| `./build-app.sh --install` | Build, copy to `/Applications` and open |
| `./build-app.sh --universal --dmg` | Apple Silicon + Intel build and a disk image |
| `./build-app.sh --test` | Run the core checks |

## Releasing

Push a tag and GitHub Actions does the rest:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The Release workflow builds a universal app, packages `WhyPort.dmg`, and attaches it to a GitHub release together with a filled-in `whyport.rb` Homebrew cask. Copy that file into `Casks/` of the tap repository `ozers/homebrew-whyport`, and `brew install --cask ozers/whyport/whyport` works.

## How it works

1. `lsof` lists TCP sockets in `LISTEN` and the ones that are `ESTABLISHED`.
2. `ps` gives the whole process table: commands, parents, uptime, memory and CPU. Walking up from the listener through launchers such as npm, pnpm, yarn, bun, `go run` and `cargo run` finds the group that belongs to one server.
3. Each working directory is walked up to the nearest `package.json`, `Cargo.toml`, `go.mod`, `pyproject.toml`, `build.gradle` or similar, and `.git/HEAD` gives the branch.
4. When Docker holds a port, `docker ps` maps it to the container.

It rescans every 2 seconds while the popover is open and every 10 seconds in the background.

## Command line

The first version was a Node CLI, and it is still here:

```bash
node src/cli.js            # live table
node src/cli.js 3000       # why 3000 is open
node src/cli.js kill 3000
```

## License

[MIT](LICENSE)

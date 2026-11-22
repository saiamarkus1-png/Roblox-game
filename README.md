# Studio Hub

A Discord-style hub for your Roblox games. It has two parts:

- **In-game hub** (`src/`): a panel inside your Roblox game. It has a channel list for each game, live chat, a 4-game grid, pop-out windows and Play buttons that teleport players.
- **Web hub** (`web/StudioHub.html`): the same idea as a web page for planning your games outside Roblox. Open it in Chrome.

## What the in-game hub does

- Press **H** or tap the **Studio Hub** button in the bottom-left corner to open it.
- **Left rail**: one icon per game, plus Home and Grid.
- **Channels**: every game has `#lobby`, `#playtest` and `#launch`. Everyone in the server can chat in them, and messages go through Roblox's text filter.
- **Grid**: shows 1, 2 or 4 games side by side. Use `<` `>` on a panel to change which game it shows.
- **Pop out**: turns a game into a floating window you can drag by its title bar and resize from the corner. Up to 4 can be open at once. **Dock** puts a window back into the grid.
- **Play**: teleports the player to that game. If they're already in it, the button says "You're here". Games without a place ID say "Coming soon".

## Put it in your game

### Option A: copy and paste (no extra tools)

In Roblox Studio, open your game, then:

1. **ReplicatedStorage**: add a **Folder** named `StudioHub`. Inside it, add a **ModuleScript** named `HubConfig` and paste in `src/shared/HubConfig.luau`.
2. **ServerScriptService**: add a **Script** named `StudioHub` and paste in `src/server/HubServer.server.luau`.
3. **StarterPlayer > StarterPlayerScripts**: add a **LocalScript** named `StudioHub` and paste in `src/client/HubClient.client.luau`.
4. Press **Play** and then press **H**.

### Option B: Rojo

If you use [Rojo](https://rojo.space), run `rojo serve` in this folder and connect from the Rojo plugin in Studio. `default.project.json` puts each file in the right place.

## Add your games

Open `HubConfig` and edit the `Games` list. For each game:

- `name`: shown in the hub.
- `placeId`: the number in the game's link. For `https://www.roblox.com/games/1234567890/My-Game` that's `1234567890`. Use `0` if the game isn't published yet.
- `status`: `"Idea"`, `"Building"`, `"Playtesting"`, `"Launched"` or `"Paused"`.
- `color` and `blurb`: the icon color and a one-line description.

The four games already in the file are examples. Replace them with your own.

## Good to know

- **Teleports don't work in Studio.** Test the Play button in a published game. The game you teleport to has to be public, or private with you allowed in.
- **Chat lasts while the server runs.** Each server keeps the last 50 messages per channel. Saving chat between servers would need DataStores. That's a possible next step.
- **Roblox can't show one game running inside another.** The panels show each game's chat, info and thumbnail, and Play takes you there.

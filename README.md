# FS25_LiquidManureTransfer

A Farming Simulator 25 mod that automatically transfers liquid manure from animal husbandries into nearby production
points that use it as an input — for example a biogas plant connected directly to a cow barn. No more slurry tanker
shuttle runs between the barn and the plant.

## How it works

Once per in-game hour (on the server), the mod:

1. Collects all production points that have **liquid manure as a production input** (e.g. a biogas plant). Productions
   that merely have a storage slot for liquid manure but no recipe consuming it are ignored.
2. For every animal husbandry with a liquid manure output, finds those productions that
    - belong to the **same farm** as the husbandry, and
    - are within the configured **transfer range** (distance between the two buildings).
3. Moves as much liquid manure as possible from the husbandry into the production's input storage, nearest production
   first, limited only by the target's free capacity.

## Settings

The mod adds a **Liquid Manure Transfer** section to _Ingame → Game Settings_:

| Setting        | Values                         | Default |
|----------------|--------------------------------|---------|
| Transfer range | 100 m – 1000 m in 100 m steps  | 300 m   |
| Log level      | Error / Warning / Info / Debug | Info    |

At **Info** level an hourly summary is logged when something was transferred; **Debug** additionally logs every
individual husbandry → production transfer with amount and distance.

Settings are stored in `modSettings/FS25_LiquidManureTransfer.xml` in your game profile folder.

## Multiplayer

Fully multiplayer compatible:

- When a client changes a setting, it is sent to the server, applied there, and broadcast to all other clients.
- Newly joining clients receive the current server settings automatically, so the settings menu always shows the server
  state.
- The transfer itself only runs on the server; fill levels reach the clients through the game's normal storage
  synchronization.

## Console commands

| Command                     | Description                                                       |
|-----------------------------|-------------------------------------------------------------------|
| `lmtPrintSettings`          | Print the current settings                                        |
| `lmtSetDistance <100-1000>` | Set the transfer range in meters                                  |
| `lmtSetLogLevel <1-4>`      | Set the log level (1=Error, 2=Warning, 3=Info, 4=Debug)           |
| `lmtTransferNow`            | Run a transfer pass immediately (server only, useful for testing) |

## Project structure

```
modDesc.xml                                        Mod descriptor (multiplayer supported)
icon_LiquidManureTransfer.dds                      Mod icon (placeholder, replace before release)
l10n/lang_en.xml, lang_de.xml                      English and German texts
src/LiquidManureTransfer.lua                       Core logic: hourly transfer, settings, logging
src/LiquidManureTransferChangeSettingsEvent.lua    Multiplayer settings sync event
src/LiquidManureTransferSettings.lua               Settings section in the game settings menu
```

# Trainer Talk

A [Gen1Recomp](https://github.com/bryanthaboi/gen1recomp) mod that adds character voice lines to a handful of moments — starting a New Game, Continuing a save, landing hits and status effects in battle, and rare day/night ambient lines — with the music briefly ducking underneath each one.

Built as a companion to the [Crystal](https://github.com/dburton95/crystal) player mod — the voice lines are Kris's lines from *Pokémon Masters EX*, so if you're already using Crystal to look the part, Trainer Talk gives her a voice to match. It works fine on its own too, without Crystal installed. A CHARACTER option lays the groundwork for other voice packs down the line (Jessie is next up — see Known limitations).

## Features

- A single fixed voice line plays on **New Game**
- One of several random voice lines plays on **Continue**, so reloading a save doesn't feel identical every time
- Occasional (~15%) voice line on landing a hit in battle, and a rarer (~10%) one on inflicting a status effect — timed so hits land after the move animation resolves, and hit/status lines can't play back-to-back
- Very rare (~5%) ambient lines on genuine day/night transitions
- Background music ducks briefly while a line plays, so it isn't buried — the duck duration is adjustable
- In-game settings (Mods manager): **VOICE LINES** on/off, **VOICE VOL** (0-7, same scale as Music/SFX/Pikachu), **DUCK TIME** (0-5s, half-second steps), and **CHARACTER** select
- Works on Gen 1 (Red/Blue/Yellow) and Gen 2 (Gold)

## Installation

1. Download the latest release `.zip` from the [Releases](../../releases) page.
2. In-game: **MODS → Import mod .zip**, or extract manually into your Gen1Recomp `mods/` folder:
   - Windows: `%APPDATA%\love\pokemon-love2d\mods\`
   - macOS: `~/Library/Application Support/LOVE/pokemon-love2d/mods/`
   - Linux: `~/.local/share/love/pokemon-love2d/mods/`
3. Restart the game.
4. Open the **MODS** panel, select **Trainer Talk**, and confirm it shows as `ENABLED`. VOICE LINES, VOICE VOL, DUCK TIME, and CHARACTER are all set from this same screen.

## How it works

Gen1Recomp doesn't expose a hook that fires directly on a title-screen button press, so New Game / Continue are handled via:

- `intro.oak_speech.finished` — fires once the player finishes the New Game naming/intro sequence
- `save.loaded` — fires after an existing save is read and validated (Continue)

Battle lines hook `battle.damage_dealt` and `battle.status_inflicted`, each gated behind a chance roll and a shared cooldown so they stay occasional rather than constant. Day/night lines hook `world.tod_changed`, matching on Gold's `MORN`/`DAY`/`NITE`/`DARK` daytime values — note that Gen 1 has no built-in day/night clock, so these will mostly stay quiet on Red/Blue/Yellow unless another mod adds one.

Music ducking hooks `music.volume` and scales it down for a configurable window (DUCK TIME) after any line starts.

## Structure

`main.lua` is a thin entry point that just requires `voice.lua` and calls `voice.init(mod)` — the same pattern Crystal itself uses (`main.lua` → per-feature module → `.init(mod)`). This is meant to make Trainer Talk easy to fold directly into another mod: copy `voice.lua` and the `assets/` folder into an existing mod's folder, `require` it from that mod's own `main.lua`, and call `.init(mod)` alongside its other features.

## Assets

Sound files live under `assets/<character>/`, matching whichever value is selected in the CHARACTER option:

- `assets/kris/new_game.ogg` — plays on New Game
- `assets/kris/continue1.ogg` through `continue4.ogg` — random pool for Continue
- `assets/kris/hit1.ogg`, `hit2.ogg` — random pool on landing a hit
- `assets/kris/status1.ogg` — plays on inflicting a status effect
- `assets/kris/night1.ogg`, `night2.ogg` — random pool for night
- `assets/kris/morning1.ogg` — plays on morning

## Known limitations

- Jessie is selectable under CHARACTER but only has a New Game line so far — everything else stays silent with her selected until more of her lines are added
- Day/night lines are effectively Gold-only until Gen 1 has a real day/night clock (its own or another mod's)
- No per-save variation — every save shares the same settings

## Credits

- Voice lines: Kris, *Pokémon Masters EX* (DeNA / The Pokémon Company)
- Built to pair with [Crystal](https://github.com/dburton95/crystal) by dburton95

## Contributing

Forks and collaboration are welcome — whether that's swapping in your own voice lines, hooking additional events, or general improvements. Feel free to open a PR or an issue.

## License

MIT — see [LICENSE](LICENSE).

## Disclaimer

This is an unofficial fan-made mod for gen1recomp. It is not affiliated with or endorsed by Nintendo, Game Freak, The Pokémon Company, or the gen1recomp maintainers. No Pokémon ROM is included.
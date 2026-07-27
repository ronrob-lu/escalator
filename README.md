# escalator — Luanti (Minetest) Mod

A fully functional escalator system that transports **players, NPCs, and mobs**
smoothly along any diagonal staircase.

---

## Features

| Feature | Detail |
|---|---|
| **Controller block** | `escalator:controller` – place at the base of a staircase |
| **Auto-detection** | Direction and orientation detected automatically from stair layout |
| **Transport** | Moves players and mobs via velocity override |
| **Legacy mob support** | Positional nudge for mobs without `set_velocity` |
| **Performance** | Scans only the active stair-path; no global entity sweeps |
| **Tunable** | All speeds and lengths configurable via the settings panel |
| **Cross-gamepack** | Works with MTG, VoxeLibre/MineClone2, and any game with stair nodes |

---

## Compatibility

- **Luanti** (formerly Minetest) ≥ 5.6
- **MTG (Minetest Game)** — uses the `stair` group
- **VoxeLibre / MineClone2** — uses the `mcl_stairs_half` group
- Any other game whose stair nodes belong to the `stair` group or have `:stair` in their name
- **mobs_redo / mobs_monster** — optional; supported via velocity/position fallback

No hard dependencies — the mod loads on any game pack.

---

## Quick-start

1. **Copy** the `escalator/` folder into your game's `mods/` directory.
2. **Enable** the mod in the Content / Mods menu or `minetest.conf`.
3. **Craft** the controller:

```
  [ mese_crystal ]
  [steel][steel][steel]
  [steel][     ][steel]
```

4. **Build** a diagonal staircase of any stair nodes rising away from where you'll
   place the controller. Any stair type recognised by your game will work.
5. **Place** the controller at the bottom (or top) of the staircase.
6. **Right-click** the controller — it will report the detected direction,
   orientation, and step count.
7. Step onto any stair — you'll be smoothly carried along!

---

## Staircase construction example

For an **Up** escalator facing **North** (`-Z` axis):

```
         [stair] ← step 4  (ctrl.x, ctrl.y+4, ctrl.z-4)
        [stair]  ← step 3
       [stair]   ← step 2
      [stair]    ← step 1
[CTRL]           ← controller at (x, y, z)
```

The controller scans up to `escalator_max_stair_length` (default 32) steps along
each diagonal. Scanning stops automatically when two consecutive stair positions
are absent. The orientation and direction (up/down) are inferred from whichever
diagonal has the most stair nodes — no manual configuration needed.

---

## Configuration

Settings can be changed in the Luanti main-menu under **Settings → Mods → escalator**,
or by adding them to `minetest.conf`:

| Setting | Default | Range | Description |
|---|---|---|---|
| `escalator_h_speed` | `2.5` | 0.5 – 5.0 | Horizontal speed (nodes/s) |
| `escalator_v_speed` | `3.0` | 0.5 – 5.0 | Vertical speed (nodes/s) |
| `escalator_max_stair_length` | `32` | 4 – 128 | Max stair nodes scanned |
| `escalator_timer_interval` | `1.0` | 0.05 – 1.0 | Controller refresh interval (s) |

---

## Debug command

```
/escalator_info
```

Stand on a stair to see which escalator it belongs to and its direction, or look
at a controller (within 12 nodes) to force a fresh scan and report step count.

---

## License

MIT – do whatever you want, attribution appreciated.

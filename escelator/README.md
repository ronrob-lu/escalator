# escalator — Luanti (Minetest) Mod

A fully functional escalator system that transports **players, NPCs, and mobs**
smoothly along a diagonal stair incline built from `stairs:stair_tinblock` nodes.

---

## Features

| Feature | Detail |
|---|---|
| **Controller block** | `escalator:controller` – place at the base of a staircase |
| **Direction** | Configurable **Up** or **Down** per controller |
| **Orientation** | North / South / East / West cardinal facing |
| **Transport** | Moves players, NPCs, and mobs via velocity override |
| **Legacy mob support** | Positional nudge via ABM for mobs without `set_velocity` |
| **Stack rule** | Controllers stack up to **10 high**, enforced on placement |
| **Formspec UI** | Right-click the controller to configure |
| **Performance** | Scans only the active stair-path; no global entity sweeps |
| **Tunable** | All speeds and lengths configurable via `settingtypes.txt` |

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

4. **Build** a staircase of `stairs:stair_tinblock` nodes rising diagonally from
   where you'll place the controller.
5. **Place** the controller at the bottom (or top) of the staircase.
6. **Right-click** the controller and set:
   - **Direction** – Up or Down.
   - **Orientation** – the cardinal direction the stairs face away from the controller.
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

The controller scans up to `MAX_STAIR_LENGTH` (default 32) steps along the diagonal.
Scanning stops automatically when two consecutive stair positions are absent.

---

## Configuration (`settingtypes.txt`)

| Setting | Default | Description |
|---|---|---|
| `escalator_h_speed` | `1.5` | Horizontal speed (nodes/s) |
| `escalator_v_speed` | `1.5` | Vertical speed (nodes/s) |
| `escalator_max_stair_length` | `32` | Max stair nodes scanned |
| `escalator_timer_interval` | `0.15` | Controller timer interval (s) |
| `escalator_max_stack` | `10` | Max controller stack height |

---

## Debug command

```
/escalator_info
```
Look at a controller (within 8 nodes) and run this command to see its current
configuration and how many stair steps were detected.

---

## Compatibility

- **Luanti** (formerly Minetest) ≥ 5.6
- **stairs** mod (standard in almost all games)
- **mobs_redo / mobs_monster** – supported via ABM positional nudge fallback
- **MTG (Minetest Game)** – full compatibility

---

## License

MIT – do whatever you want, attribution appreciated.

# Idle City

An original, cartoon-style Android idle city game. Collect income, unlock
buildings and meet a growing cast of residents with opinions about everything.

## Play

- Tap a floating coin to collect a building's income and start its next cycle.
- Open **Buildings**, choose an unlocked building, then tap an empty tile to
  preview it and tap the same tile again to buy and place it. Use **Cancel
  placement** to change your mind; drag to pan.
- Open **People** to see residents and their unlock levels. Tap an unlocked
  resident in the city for a little local wisdom.
- Progress is saved on the device. A building holds one completed cycle while
  the game is closed; it does not accumulate multiple cycles.

The game starts with a house and 40 coins. Collecting also earns XP, unlocking
the café and Nora at level 2 (3 cumulative XP), then the bakery and Pip at
level 3 (10 cumulative XP). Milo is available from the start. These values
are a starting point for playtesting.

## Development

Open `project.godot` in **Godot 4.7.2 stable** and run the project. The game
uses the GL Compatibility renderer and is designed for landscape Android; a
mouse works for desktop development. Generated original illustrations live
under `assets/`.

Run the game and debug-signing tests from the repository root:

```sh
godot --headless --path . --script tests/test_economy.gd
godot --headless --path . --script tests/test_ui.gd
godot --headless --path . --script tests/test_clock_economy.gd
godot --headless --path . --script tests/test_save_recovery.gd
godot --headless --path . --script tests/test_save_retry.gd
bash tests/test_debug_signing.sh
```

The Android export preset builds a debug APK at `build/idle-city-debug.apk`.
Install the matching Godot export templates and configure the Android SDK and
JDK in Godot's editor settings before exporting. Release signing and Play Store
publishing are outside this prototype.

CI signs trusted builds with a persistent, debug-only keystore stored in the
`IDLECITY_DEBUG_KEYSTORE_BASE64` repository Actions secret. Keep a protected
backup of that key; changing it means Android cannot install the new APK over
an APK signed with the old key. Local debug exports use the developer's own
configured key and may not be update-compatible with CI artifacts. Builds
from fork pull requests never receive the persistent key: they use an
ephemeral key and publish a separately named `idle-city-untrusted-debug-apk`
artifact. Such artifacts are not update-compatible with trusted builds or
other fork runs. Previously issued APKs used per-run keys and likewise cannot
be upgraded to the new trusted APK without an uninstall and loss of local data.

The APK includes 32-bit ARM, 64-bit ARM, and 64-bit x86 native libraries.

# Bomberman 8-Bit for Android

A small, colorful retro pixel-style maze-bombing game prototype made with Godot 4. It is inspired by the classic maze-bombing genre and is not affiliated with or a copy of Nintendo's original game.

## First prototype

- Retro maze with solid walls and breakable blocks
- Player movement and bomb placement
- Short-range explosions that destroy blocks and defeat enemies
- On-screen touch controls plus keyboard controls for testing
- Android APK exported by GitHub Actions

## Build without a powerful PC

Every push to `main` starts **Build Android APK**. You can also run it manually:

1. Open the repository's **Actions** tab.
2. Select **Build Android APK**.
3. Choose **Run workflow** if you want to start a build manually.
4. Open the completed run and download the `Bomberman8Bit-APK` artifact.
5. Extract the ZIP file to get the APK, then install it on your Android device.

The first build may fail if the Godot CI image does not contain the matching Android export templates. If that happens, the workflow log will show the missing component and we can adjust the build setup.

## Controls

- Move: WASD or arrow keys
- Bomb: Space
- Touch: use the on-screen controls
- Restart after a loss/win: R on keyboard or tap the screen

This is an early prototype. Sprites, sound, levels, power-ups, and more polished movement can be added in later commits.

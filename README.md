# Intervals

Walk/run interval timer for iPhone. Voice cues keep working with the screen locked and play over a podcast or music.

## How the audio works

- A silent looping track keeps the app alive in the background (`UIBackgroundModes: audio`).
- At each change the app says one word: "Run" or "Walk". It says "Done" at the end. No vibration.
- During the cue, the podcast or music gets quieter, then returns to full volume.
- Cues play in silent mode, because the app uses the `.playback` audio category, which ignores the silent switch.
- Timing comes from the clock, not from counting ticks, so it never drifts.

## Build the .ipa (no Mac needed)

Push this folder to a GitHub repo. The workflow in `.github/workflows/build.yml` builds on a macOS runner. Open the **Actions** tab, open the latest run, and download **Intervals-ipa**.

## Install with Sideloadly (Windows)

1. Install iTunes and iCloud from Apple's website (not the Microsoft Store versions), then install Sideloadly.
2. Connect the iPhone by USB and tap **Trust** on the phone.
3. Drag `Intervals.ipa` into Sideloadly, enter your Apple ID, press **Start**.
4. On the iPhone: Settings → Privacy & Security → **Developer Mode** → on (the phone restarts).
5. Settings → General → VPN & Device Management → your Apple ID → **Trust**.

A free Apple ID signs the app for 7 days. After that, run Sideloadly again with the same .ipa. Your history is kept.

## First run

Start a podcast, open the app, tap **Test cues (30 s)**, and lock the phone. You should hear three cues.

# Installation and controls

## Requirements

- A Kindle supported by KOReader, with a working jailbreak and a way to launch KOReader. Follow the [official Kindle installation guide](https://github.com/koreader/koreader/wiki/Installation-on-Kindle-devices) for the appropriate package and launcher for your device.
- Wi-Fi for aircraft and ISS updates. A power source is recommended for a continuously running desk display.

Kindle Sky is a KOReader plugin. This repository does not bundle KOReader, a jailbreak, or a launcher.

## Install the plugin

1. Exit KOReader and connect the Kindle in USB Drive Mode.
2. Copy the complete `kindlesky.koplugin` directory into the Kindle's `koreader/plugins/` directory. On the Kindle, that path is normally `/mnt/us/koreader/plugins/kindlesky.koplugin/`.
3. Safely eject the Kindle, unplug it, and restart KOReader.
4. Open **Tools → Kindle Sky → Set location and refresh**. Enter your latitude and longitude in decimal degrees. The repository default, New York City, is an example. The initial radius is 40 nautical miles and the data refresh interval is 120 seconds; the shortest allowed interval is 60 seconds.
5. Select the display orientation and choose **Start display**.

If the menu entry does not appear, check that `main.lua`, `_meta.lua`, `data.lua`, `rotation.lua`, `time.lua`, and `visuals.lua` are all inside the same `kindlesky.koplugin` directory, then restart KOReader.

## Use the display

The display opens on a combined Home view. It cycles through Home, Aircraft, and ISS every 90 seconds. If no aircraft are available, it skips Aircraft. **Auto-cycle views (90 s)** in the Kindle Sky menu turns automatic changes on or off.

Tap a radar dot for that aircraft's details. On the Aircraft view, tap the left side to move to the next aircraft, the right side for ISS, or the header to return Home. On Home, tap the pass area for ISS. Hold anywhere to exit. Manual taps restart the automatic view timer.

A predicted visible ISS pass within ten minutes holds the ISS view on screen until the pass ends. A newly detected aircraft emergency takes the Aircraft view for one cycle. These are on-screen changes while the app is open, not notifications that wake a sleeping Kindle.

Kindle Sky requests that the device stay awake while its display is open and restores normal sleep behavior when closed. This and Wi-Fi use more battery than reading; external power is recommended. If KOReader exits unexpectedly and the Kindle then refuses to sleep, open KOReader's **Keep alive** control and close its dialog to reset the power-manager setting, or restart the Kindle.

## Time zone

The header clock and predicted pass times currently display Eastern time, including EST/EDT transitions. Changing the latitude and longitude does not change the display time zone. If your Kindle is elsewhere, adapt `time.lua` before relying on the displayed local time.

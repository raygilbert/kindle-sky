# Installation and controls

## Requirements

- A Kindle supported by KOReader, with a working jailbreak and a way to launch KOReader. Follow the [official Kindle installation guide](https://github.com/koreader/koreader/wiki/Installation-on-Kindle-devices) for the appropriate package and launcher for your device.
- Wi-Fi for aircraft, orbital catalog, and supported local rail updates. A power source is recommended for a continuously running desk display.

Kindle Horizon is a KOReader plugin. This repository does not bundle KOReader, a jailbreak, or a launcher.

## Install the plugin

1. Exit KOReader and connect the Kindle in USB Drive Mode.
2. Copy the complete `kindlesky.koplugin` directory into the Kindle's `koreader/plugins/` directory. On the Kindle, that path is normally `/mnt/us/koreader/plugins/kindlesky.koplugin/`.
3. Safely eject the Kindle, unplug it, and restart KOReader.
4. Open **Tools → Kindle Horizon → Set location and refresh**. Enter your latitude and longitude in decimal degrees. The repository default, New York City, is an example. The initial radius is 40 nautical miles and the data refresh interval is 120 seconds; the shortest allowed interval is 60 seconds.
5. Select **Time zone** and the display orientation, then choose **Start display**.

If the menu entry does not appear, check that `main.lua`, `_meta.lua`, `data.lua`, `rotation.lua`, `time.lua`, `trains.lua`, `satellites.lua`, and `visuals.lua` are all inside the same `kindlesky.koplugin` directory, then restart KOReader.

## Use the display

The display opens on a combined Home view. It cycles through Home, Aircraft, and Satellites every 90 seconds, adding Trains where the saved coordinates have a supported local feed. If no aircraft are available, it skips Aircraft. **Auto-cycle views (90 s)** in the Kindle Horizon menu turns automatic changes on or off.

Tap a radar dot for that aircraft's details. On the Aircraft view, tap the left side to move to the next aircraft, the right side for Satellites, or the header to return Home. On Home, tap the satellite area for the sky map. In supported regions, tap the Satellite view to open Trains, then tap again to return Home. **Tools → Kindle Horizon → Show nearby trains** opens that view directly. Hold anywhere to exit. Manual taps restart the automatic view timer.

The saved latitude and longitude select the rail provider: SEPTA Regional Rail in the Philadelphia region, TfL rail arrivals in Greater London, and no train panel elsewhere. Changing coordinates does not detect your physical location automatically; set them again when you move. SEPTA shows approximate positions within the configured radius. London shows predictions at the nearest station within 1.5 km. See [data sources and limitations](DATA_AND_LIMITS.md).

The sky map shows catalog satellites at least 10° above the saved location's horizon. It downloads CelesTrak orbital elements at most once every two hours, caches them across restarts, and estimates positions locally between downloads. The ISS appears when overhead. If CelesTrak reports an HTTP error, the plugin pauses catalog requests until you choose **Retry satellite catalog**. A newly detected aircraft emergency takes the Aircraft view for one cycle.

Kindle Horizon requests that the device stay awake while its display is open and restores normal sleep behavior when closed. This and Wi-Fi use more battery than reading; external power is recommended. If KOReader exits unexpectedly and the Kindle then refuses to sleep, open KOReader's **Keep alive** control and close its dialog to reset the power-manager setting, or restart the Kindle.

## Time zone

The header clock uses **Tools → Kindle Horizon → Time zone**. **Auto** uses the device's zone when KOReader reports a non-UTC zone. If KOReader reports UTC, Auto falls back to Eastern to avoid the UTC clock seen on some Kindle launchers. Choose **Device time zone** to use the device setting exactly, including UTC. You can also select Eastern, Central, Mountain, Pacific, Alaska, Arizona, Hawaii, or UTC directly. The North American choices handle their daylight-saving transitions; Arizona and Hawaii stay on standard time. Changing the latitude and longitude does not change this setting.

On a Kindle whose native clock is local but KOReader reports UTC, choose your time zone explicitly. The clock is based on the Kindle's system time, so an incorrect device date or time will still produce an incorrect display.

# Kindle Sky

Kindle Sky turns a jailbroken Kindle running [KOReader](https://github.com/koreader/koreader) into an e-ink desk display for nearby aircraft and the International Space Station. It runs on the Kindle itself; no companion computer is needed after installation. Wi-Fi is required for live data.

The idea was inspired by [this e-paper desk display](https://www.reddit.com/r/eink/comments/1xbw3xi/i_built_an_epaper_desk_display_that_shows_nearby/). Kindle Sky is an independent KOReader plugin, not a port of that project's code.

## What you see

- A home view with nearby aircraft, radar, a featured aircraft, and the next predicted visible ISS pass.
- Aircraft details with reported callsign, type, registration, distance, bearing, altitude, speed, and a **representative** monochrome silhouette. The silhouette shows a broad aircraft category; it is not a photo or an exact depiction of that registration.
- An ISS view with current position, local sky direction and elevation, a solar-array diagram, and the next predicted visible pass.
- Automatic Home → Aircraft → ISS view changes every 90 seconds. When several aircraft are nearby, Aircraft turns favor emergency, reported military, and selected unusual types while avoiding consecutive repeats where possible. A newly detected emergency opens its detail view immediately.
- Data-age and **STALE** indicators when a feed stops updating. The display keeps the Kindle awake while it runs and restores normal sleep behavior when closed.

## Quick start

1. Install KOReader on a supported, jailbroken Kindle using [KOReader's Kindle guide](https://github.com/koreader/koreader/wiki/Installation-on-Kindle-devices).
2. Copy the `kindlesky.koplugin` folder from this repository into `koreader/plugins/` on the Kindle USB drive. Restart KOReader.
3. Open **Tools → Kindle Sky → Set location and refresh**. Enter your own latitude and longitude before starting. The source ships with **New York City example coordinates**, not your location.
4. Choose **Landscape display** or **Portrait display**, then **Start display**. Tap the radar or aircraft area for aircraft details, tap the pass area for ISS details, and hold the screen to exit.

See [installation and controls](docs/INSTALLATION.md) for the complete setup and [data sources and limitations](docs/DATA_AND_LIMITS.md) before using the feeds.

## Current scope

Kindle Sky has been tested on one older Kindle with KOReader. Other models and firmware versions may need layout or launch adjustments. The clock and ISS pass labels currently use **Eastern time (EST/EDT)** even if you set a location in another time zone. Aircraft and satellite positions are approximate, and pass alerts appear only while Kindle Sky is open.

The plugin source and vector-like raster diagrams are original to this project. KOReader, the launcher used to start it, and the live data services are separate third-party projects. Their binaries are not included in this repository. See [data sources and limitations](docs/DATA_AND_LIMITS.md) for attribution and service terms.

## License

Kindle Sky's code, diagrams, and documentation are available under the [MIT License](LICENSE). You may use, modify, and distribute them, including commercially, with the copyright and license notice. The live data feeds have their own terms; in particular, the public adsb.fi endpoint is limited to personal, non-commercial use. See [data sources and limitations](docs/DATA_AND_LIMITS.md) before using those services in another project.

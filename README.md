# Kindle Sky

Kindle Sky turns a jailbroken Kindle running [KOReader](https://github.com/koreader/koreader) into an e-ink desk display for nearby aircraft, the International Space Station, and supported local rail feeds. It runs on the Kindle itself; no companion computer is needed after installation. Wi-Fi is required for live data.

The idea was inspired by [this e-paper desk display](https://www.reddit.com/r/eink/comments/1xbw3xi/i_built_an_epaper_desk_display_that_shows_nearby/). Kindle Sky is an independent KOReader plugin, not a port of that project's code.

## What you see

- A home view with nearby aircraft, radar, a featured aircraft, and the next predicted visible ISS pass.
- Aircraft details with reported callsign, type, registration, distance, bearing, altitude, speed, and a **representative** monochrome silhouette. Distinct outlines include widebody jets, airliners, business jets, light prop planes, turboprops, fighters, and helicopters. The silhouette is not a photo or an exact depiction of that registration.
- An ISS view with current position, local sky direction and elevation, a solar-array diagram, and the next predicted visible pass.
- A location-dependent train view with a simple railcar diagram: approximate SEPTA Regional Rail train positions near Philadelphia, or TfL station arrival predictions near London. In other locations, the train view is omitted until a supported feed is added.
- Automatic Home → Aircraft → ISS → Trains view changes every 90 seconds where a train feed is supported. When several aircraft are nearby, Aircraft turns favor emergency, reported military, and selected unusual types while avoiding consecutive repeats where possible. A newly detected emergency opens its detail view immediately.
- Data-age and **STALE** indicators when a feed stops updating. The display keeps the Kindle awake while it runs and restores normal sleep behavior when closed.

## Quick start

1. Install KOReader on a supported, jailbroken Kindle using [KOReader's Kindle guide](https://github.com/koreader/koreader/wiki/Installation-on-Kindle-devices).
2. Copy the `kindlesky.koplugin` folder from this repository into `koreader/plugins/` on the Kindle USB drive. Restart KOReader.
3. Open **Tools → Kindle Sky → Set location and refresh**. Enter your own latitude and longitude before starting. The source ships with **New York City example coordinates**, not your location.
4. Choose **Time zone** if you want a specific local clock, choose **Landscape display** or **Portrait display**, then **Start display**. Tap the radar or aircraft area for aircraft details, tap the pass area for ISS details, tap the ISS view for trains where supported, and hold the screen to exit. **Show nearby trains** opens the rail view directly when your saved location has a supported feed.

See [installation and controls](docs/INSTALLATION.md) for the complete setup and [data sources and limitations](docs/DATA_AND_LIMITS.md) before using the feeds.

Keep your own coordinates and Kindle settings out of public issues and pull requests. The public source contains example coordinates; installed settings live on the device. HTTPS requests verify certificate chains using KOReader's CA bundle, but the bundled LuaSec build does not verify hostnames. See [data sources and limitations](docs/DATA_AND_LIMITS.md) for the security boundary.

## Current scope

Kindle Sky has been tested on one older Kindle with KOReader. Other models and firmware versions may need layout or launch adjustments. The clock and ISS pass labels use the selected time zone. **Auto** uses the device zone when KOReader reports a non-UTC zone, then falls back to Eastern; change it in the menu if that does not match your location. The train feed uses the saved coordinates; it does not detect where the Kindle is physically located. Aircraft, satellite, and SEPTA train positions are approximate. TfL data is station arrival predictions, not train positions. Pass alerts appear only while Kindle Sky is open.

The plugin source and vector-like raster diagrams are original to this project. KOReader, the launcher used to start it, and the live data services are separate third-party projects. Their binaries are not included in this repository. See [data sources and limitations](docs/DATA_AND_LIMITS.md) for attribution and service terms.

## License

Kindle Sky's code, diagrams, and documentation are available under the [MIT License](LICENSE). You may use, modify, and distribute them, including commercially, with the copyright and license notice. The live data feeds have their own terms; in particular, the public adsb.fi endpoint is limited to personal, non-commercial use. See [data sources and limitations](docs/DATA_AND_LIMITS.md) before using those services in another project.

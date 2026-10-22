# Data sources and limitations

| Display data | Provider | How Kindle Sky uses it |
| --- | --- | --- |
| Nearby aircraft | [adsb.fi open data](https://github.com/adsbfi/opendata/blob/main/README.md) | One geographic request per refresh, normally every two minutes. |
| ISS position | [Where the ISS at?](https://docs.wheretheiss.at/w/developer) | Current ISS position, altitude, and speed. |
| Visible ISS pass | [issinfo.net next-pass JSON](https://issinfo.net/next-pass) | Next predicted visible pass for the configured coordinates, queried no more than once an hour after a successful request. |

The [adsb.fi open-data terms](https://github.com/adsbfi/opendata/blob/main/README.md) limit the public endpoint to personal, non-commercial use, request attribution with a link, and rate-limit public requests to one per second. Kindle Sky credits adsb.fi on screen and uses a longer default interval. The [Where the ISS at? documentation](https://docs.wheretheiss.at/w/developer) describes a rate limit of roughly one request per second. Check each provider's current terms before deploying beyond personal use.

Aircraft positions and metadata can be missing, stale, or wrong. The "reported military" label comes from a feed flag and is not independent verification. The rare-type list is a small, hand-selected set, not a comprehensive rarity database. Silhouettes are representative diagrams, not exact airframes. ISS visibility predictions depend on the configured location, time, weather, and the provider's orbital data.

Kindle Sky sends the configured latitude and longitude to adsb.fi and issinfo.net in API requests. It sends no account credentials and has no project-operated server. If a request fails, previously received data is marked **STALE** and aircraft or ISS positions are removed after ten minutes without an update.

The plugin's LuaSec requests on the older tested Kindle currently run without TLS certificate verification. These requests fetch public display data; they should not be treated as authenticated alerts. The clock and pass labels use the selected time zone; Auto falls back to Eastern when KOReader reports UTC. The display does not wake a sleeping Kindle to announce a pass.

KOReader is a separate project; install it from its [official release and installation documentation](https://github.com/koreader/koreader). The plugin does not include KOReader binaries or a launcher. The project's e-ink diagrams and plugin logic were created for Kindle Sky, inspired by the [original desk-display idea](https://www.reddit.com/r/eink/comments/1xbw3xi/i_built_an_epaper_desk_display_that_shows_nearby/).

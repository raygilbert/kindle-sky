# Data sources and limitations

| Display data | Provider | How Kindle Sky uses it |
| --- | --- | --- |
| Nearby aircraft | [adsb.fi open data](https://github.com/adsbfi/opendata/blob/main/README.md) | One geographic request per refresh, normally every two minutes. |
| ISS position | [Where the ISS at?](https://docs.wheretheiss.at/w/developer) | Current ISS position, altitude, and speed. |
| Visible ISS pass | [issinfo.net next-pass JSON](https://issinfo.net/next-pass) | Next predicted visible pass for the configured coordinates, queried no more than once an hour after a successful request. |
| Philadelphia-area rail | [SEPTA TrainView API](https://app.septa.org/) | Approximate Regional Rail train positions filtered to the saved coordinates and aircraft radius, normally queried every two minutes. |
| London-area rail | [TfL Unified API](https://push-api-nile.tfl.gov.uk/swagger/ui/index.html) | Finds the nearest rail station within 1.5 km of the saved coordinates, then shows its arrival predictions. These are station predictions, not train positions. |

The [adsb.fi open-data terms](https://github.com/adsbfi/opendata/blob/main/README.md) limit the public endpoint to personal, non-commercial use, request attribution with a link, and rate-limit public requests to one per second. Kindle Sky credits adsb.fi on screen and uses a longer default interval. The [Where the ISS at? documentation](https://docs.wheretheiss.at/w/developer) describes a rate limit of roughly one request per second. Check each provider's current terms before deploying beyond personal use.

Aircraft positions and metadata can be missing, stale, or wrong. The "reported military" label comes from a feed flag and is not independent verification. The rare-type list is a small, hand-selected set, not a comprehensive rarity database. Aircraft silhouettes and the train drawing are representative diagrams, not exact vehicles or liveries. ISS visibility predictions depend on the configured location, time, weather, and the provider's orbital data.

Rail coverage is chosen from the location saved in Kindle Sky. Philadelphia-area coordinates select SEPTA; Greater London coordinates select TfL; other locations skip the train view. There is no automatic GPS location detection. SEPTA TrainView may place trains approximately, especially in areas without live location data; a train's displayed line may lag its current operating segment. TfL predictions can change or be absent, and only the nearest station within 1.5 km is shown. [TfL's API portal](https://api-portal.tfl.gov.uk/products) allows 50 anonymous requests per minute; Kindle Sky normally makes one stop search when the location changes and one arrival request per two-minute refresh in London. TfL data is credited on screen and no TfL logos are used.

Kindle Sky sends the configured latitude and longitude to adsb.fi and issinfo.net in API requests. In London it also sends them to TfL for the nearest-station search. The SEPTA TrainView request has no coordinates; the Kindle filters the public train list locally. It sends no account credentials and has no project-operated server. If a request fails, previously received data is marked **STALE** and positions or predictions are removed after ten minutes without an update.

The plugin's LuaSec requests on the older tested Kindle currently run without TLS certificate verification. These requests fetch public display data; they should not be treated as authenticated alerts. The clock and pass labels use the selected time zone; Auto falls back to Eastern when KOReader reports UTC. The display does not wake a sleeping Kindle to announce a pass.

KOReader is a separate project; install it from its [official release and installation documentation](https://github.com/koreader/koreader). The plugin does not include KOReader binaries or a launcher. The project's e-ink diagrams and plugin logic were created for Kindle Sky, inspired by the [original desk-display idea](https://www.reddit.com/r/eink/comments/1xbw3xi/i_built_an_epaper_desk_display_that_shows_nearby/).

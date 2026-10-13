# Third-party icons - notice

The SVGs in `svg/` come from [Simple Icons](https://simpleicons.org) at the version recorded in
each `catalog.json` entry (`source`), recoloured with the brand colour (or `#232F3E` when the
brand colour is too light to read on white). Simple Icons is released under CC0-1.0, but not
every icon is: `catalog.json` records each icon's own `license` (for example Apache Kafka is
Apache-2.0, OpenTelemetry is CC-BY-4.0, Keycloak follows the Linux Foundation trademark policy)
and the brand `guidelines` URL when one exists.

Every logo is a trademark of its owner. The icons are here to identify the product in an
architecture diagram (nominative use); they do not imply endorsement. Check the brand
guidelines before using a diagram in marketing material.

Rebuild or extend the set with `python3 build_catalog.py --version <simple-icons version>`
(needs network access; add the slug to `ICONS` first).

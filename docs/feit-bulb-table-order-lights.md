# Feit bulb table-order lights — implemented

Code is in the Ohana Belltown Vapor tree (`ProDataMan/Ohana_Belltown`). New files:

- `server/Sources/App/PrepStation.swift`
- `server/Sources/App/TuyaCloudClient.swift`
- `server/Sources/App/LightNotifier.swift`
- `server/Tests/AppTests/LightNotifierTests.swift`

Hooks: `routes.swift` (`place` / `enter` / `deliver`), `configure.swift` (env + 5s ready poll).

Lights no-op until Tuya secrets are set. Guest ordering is unchanged if Tuya is down.

## Color map (matches `/table-orders-admin.html`)

| Signal | CSS token | Hex | Who flashes |
|---|---|---|---|
| Needs entry — kitchen | `--gold-bright` | `#f2a93c` | Server station only |
| Needs entry — sushi | area teal | `#2ec4b6` | Server station only |
| Needs entry — bar | area blue | `#3d8bfd` | Server station only |
| Confirm entered / processing | `--purple-bright` | `#8f5fd6` | That prep station + server, **3 flashes** |
| Order up / awaiting delivery | `--pink` | `#ff2f8f` | Prep station **3 flashes**; server **until delivered** |

Kitchen / sushi / bar bulbs never flash for needs-entry.

## Timing

| Event | Pattern |
|---|---|
| Guest sends ticket | Server pulses area color **30s or until Confirm Entered** |
| Confirm Entered | **3 flashes** purple at that station and server |
| `estimatedReadyAt` reached | Station **3 flashes** pink; server pulses pink **until Confirm Delivered** |
| Confirm Delivered (or guest Mark Received) | Server pink stops (unless another ticket is still up) |

Cart bursts from the same station within 2s share one server pulse.

## Menu section → station

| `section` on the order | Fixture |
|---|---|
| `drinks` | Bar |
| `sushi` | Sushi |
| `menu`, `happy_hour`, missing | Kitchen |

## Azure Container App secrets

```
TUYA_ACCESS_ID
TUYA_ACCESS_SECRET
TUYA_REGION=us
TUYA_DEVICE_ID_SERVER=<tuya device id>
TUYA_DEVICE_ID_KITCHEN=<tuya device id>
TUYA_DEVICE_ID_SUSHI=<tuya device id>
TUYA_DEVICE_ID_BAR=<tuya device id>
TUYA_COLOUR_CODE=colour_data
```

`TUYA_DEVICE_ID` (no suffix) is a server-station fallback while the other three are being installed.

Bring-up: Smart Life (not Feit app) → link account on iot.tuya.com → copy device IDs. If color commands fail, set `TUYA_COLOUR_CODE=colour_data_v2`.

Staff check: `GET /api/table-orders/lights` (logged in) returns `{ enabled, fixtures, colors }` with no secrets.

## Deploy

1. Merge this branch to `main`. `deploy-server.yml` builds and updates `ohana-belltown-server`.
2. Set the `TUYA_*` secrets on the Container App, then send a test sushi item from a table QR.

Tuya credentials stay on the server. The tablet page does not talk to the bulbs.

# NetworkManager profiles — reference only

Record of every NetworkManager connection configured on the original machine
(`vlacap-desktop`). The `.nmconnection.example` files here are **reconstructions**
from `nmcli` output, not the live files. The originals are at
`/etc/NetworkManager/system-connections/`, are `root:root` / `chmod 600`, and store
the Wi-Fi PSKs in cleartext (`psk-flags: 0`) — not readable without root, so every
example has `psk=REDACTED`.

This is here so the new machine's networking can be set up to match what the rover
actually expected — **not** a claim that all of these are needed. Decide per profile.

## To reproduce a profile on the new machine

Either recreate it with `nmcli` / the GUI from the values below, or copy the real
file off the old box:

```bash
sudo scp /etc/NetworkManager/system-connections/<name>.nmconnection \
     <newmachine>:/etc/NetworkManager/system-connections/
# on the new machine:
sudo chown root:root /etc/NetworkManager/system-connections/<name>.nmconnection
sudo chmod 600       /etc/NetworkManager/system-connections/<name>.nmconnection
sudo nmcli connection reload
```

`interface-name` on the wired profiles is `enP8p1s0` — the Tegra NIC name on this
carrier board. If the new board names its ports differently, edit that field or
remove it so the profile matches any device of the right type.

## All six profiles

| id | type | mode | ipv4 | addr | autoconnect | notes |
|---|---|---|---|---|---|---|
| `campus-eth` | ethernet | — | auto (DHCP) | — | no | wired DHCP client on `enP8p1s0` |
| `direct-link` | ethernet | — | manual | `192.168.50.1/24` | yes | wired point-to-point on `enP8p1s0`, no gateway/DNS |
| `Hotspot` | wifi | ap | shared | (NM default `10.42.0.1/24`) | no | AP, SSID `jetsontest`, WPA2 (rsn/ccmp) |
| `rover-hotspot` | wifi | ap | shared | `10.42.0.1/24` | yes (prio 10) | AP, SSID `jetsontest`, WPA2 |
| `UniEquip` | wifi | infrastructure | auto (DHCP) | — | yes (prio 100) | client, SSID `UniEquip`, WPA2-PSK |
| `TP-Link_8BA9` | wifi | infrastructure | auto (DHCP) | — | yes | client, SSID `TP-Link_8BA9`, WPA2-PSK |

`Hotspot` and `rover-hotspot` are two AP profiles for the same SSID (`jetsontest`) on
the same interface (`wlP1p1s0`); only one can be active at a time. `UniEquip` and
`TP-Link_8BA9` are site Wi-Fi clients and are location-specific.

Each `*.nmconnection.example` file mirrors one row above, with `psk` and `uuid`
stripped (NM generates a fresh `uuid` on import; fill in the real `psk` from the old
machine, or set a new one).

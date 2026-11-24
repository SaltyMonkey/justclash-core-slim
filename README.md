# JustClash Core Slim

A streamlined mihomo core for the JustClash project, intended for routers and
other devices with limited resources. Optional protocols and components are
excluded to reduce the binary size and dependencies.

The core can also be used independently of JustClash with a mihomo-compatible
configuration, subject to the differences below. This is an unofficial version;
it is not affiliated with or maintained by MetaCubeX.

## Standalone use

Download the binary for your platform from Releases, unpack it and run it with
your configuration and data directory:

```sh
./mihomo -d ./data -f ./config.yaml
```

Standard proxy listeners, routing rules, DNS, fake IP, TPROXY, supported TUN
stacks, the controller API and web UI remain available. Hysteria 2, Shadowsocks
and Snell are supported.

## Removed functionality

- EasyTier, Tailscale and ZeroTier.
- TrustTunnel, Hysteria 1 (including FakeTCP), ShadowQUIC, OpenVPN and ShadowsocksR.
- gVisor and the `mixed` TUN stack. TUN accepts only `system` and `mips`;
  unsupported stack settings are rejected. HTTP/SOCKS mixed listeners remain
  available.
- HTTP `/debug` endpoints. Ordinary logging remains available.
- Core self-update through the controller API. Update the binary through
  JustClash or replace it manually. UI and GEO database updates remain available.
- Extraction of rule providers from `BundleMRS.7z`. Ordinary local and remote
  rule-provider sources, including individual MRS files, remain supported.

Proxy providers skip nodes using excluded protocols and report a warning. An
update with no supported nodes fails and keeps the previous provider list.
Other configuration errors remain errors, including an explicitly configured
unsupported proxy outside a provider.

## Added functionality

- **Connection-count API:** `GET /connections/count` returns `{"count":N}`
  without collecting the full connection list. WebSocket clients receive the
  count immediately and then at `interval` milliseconds: default 1000, accepted
  range 100–60000. The endpoint uses the existing controller authentication.
- **Local destination resolution for SOCKS5:** `resolve-destination: true` on a
  SOCKS5 outbound resolves TCP destination names through the core's main DNS
  resolver before connecting through the proxy. It respects `ip-version` and
  defaults to `false`. `proxy-server-nameserver` still resolves the SOCKS server;
  this option does not use `direct-nameserver` for destination lookups.
- **Least-connections balancing:** `strategy: least-connections` in a
  `load-balance` group selects an available node with the fewest active
  connections relative to its share. TCP connections and UDP sessions count
  together, including pending connection attempts. Repeating a node in an
  explicit `proxies` list increases its share; filtering can deduplicate entries.
  The strategy does not keep sessions on one exit and does not support `hash-key`.

## Other differences

- **Persistent fake IP:** mappings and allocation progress are saved together,
  including replacement cleanup. Restarting the core or reloading the same range
  no longer depends on a separate allocation checkpoint. A rejected reload
  with a different range preserves the active mappings. Persistence requires
  `profile.store-fake-ip: true` and a writable cache file. To retain it across a
  router reboot, keep the data directory on persistent storage: `/tmp` is cleared
  on reboot.
- **URL-test selection:** provider refreshes rebind the selected node to the
  current instance, the first candidate is included, tolerance arithmetic avoids
  overflow, and concurrent selection updates are synchronized.
- **Fallback selection:** if the saved proxy is absent after a provider refresh,
  the group uses its first alive proxy and preserves the saved selection for
  when that proxy returns.
- **Provider retries.** An overdue provider refresh runs once at startup. Failed
  initial downloads and cache writes follow retry backoff. Automatic retries
  after HTTP `404`, `410`, or `429` wait half the configured provider
  `interval`, rounded up to whole seconds. Other retry delays triple after each
  successive failure, up to the provider interval.
- **Provider download limits.** HTTP responses larger than the provider's
  `size-limit` are rejected before parsing, preserving the previous cache.
- **GeoDAT validation.** Valid custom GeoIP and GeoSite `.dat` files can omit the
  `CN` category. The updater decodes downloaded replacements before saving them.
- **XHTTP compatibility:** corrected path/query handling, default padding and
  selected `sc-*` values for zero ranges, and import of numeric/string ranges
  and download XMUX settings from `extra`.
- **REALITY version advertisement:** the client advertises `26.11.9` instead of
  `1.8.2` for testing server-side `minVer` checks. Only the advertised version
  changes; this does not provide full feature compatibility with Xray `26.11.9`.
  ML-DSA-65 certificate verification (`mldsa65Verify`) is not implemented.
  Passing the version check does not add that verification or guarantee a
  successful connection with the server's configuration.
- **Controller behavior:** `/memory` reports actual usage from the first message.
  Individual proxy delay tests stop when their API request is cancelled.
  Request headers and TLS handshakes have a 15-second timeout, idle keep-alive
  connections close after 2 minutes, and the header-size limit is 256 KiB.
  Active requests and streaming responses have no overall read/write timeout.
- **Startup logging.** Configuration milestones and successful controller,
  inbound, DNS, and TUN starts are written to standard output at `INFO`, even
  with `log-level: error` or `log-level: silent`. The TLS controller loads its
  client CA and ECH settings before opening the listener.
- **Debug logging.** The core skips formatting `DEBUG` messages when neither
  standard output nor controller log subscribers request them.
- **HTTP proxy authentication.** A `407` response closes the client connection
  when the request body remains unread.
- **WireGuard reloads.** A replacement device waits for the previous device to
  close before starting, including during overlapping reloads.
- **TPROXY UDP cleanup:** local sockets are released after 60 seconds of
  inactivity, with coordinated cleanup when sockets are replaced.
- **Connection retries:** local socket resource exhaustion stops repeated dial
  attempts instead of immediately retrying the same resource failure.
- **HTTP/2 memory use:** the request-body scratch-buffer limit is 32 KiB per
  sending stream. This is not a limit on request size or connection throughput.
  Closed client connections stop their idle and health-check timers, avoiding
  retention of connection buffers until those timers fire.
- **MRS loading:** binary readers reuse small buffers, and zstd decoding runs
  synchronously to reduce temporary allocations while loading rule providers.
  The binary format and loaded rule representation are unchanged.
- **Custom TLS certificates:** the configuration key is `custom-certificates`.

## Releases

Stable releases follow upstream version tags. `Prerelease-Alpha` is the rolling
prerelease; its assets are replaced when a new Alpha version is published.
Runtime versions have a `-slim` suffix. Each target has one build without gVisor.

Releases include the corresponding source in `custom-core-source.tar.gz` and
Go dependency sources in `vendor.tar.gz` alongside the binaries.

## License

JustClash Core Slim is based on [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo)
and is distributed under the [GNU General Public License, version 3](LICENSE).
This is an unofficial distribution, not an official MetaCubeX release.

Some changes adapt work from mihomo contributors and other projects, including
[Citrus](https://github.com/getmikan/Citrus) and
[prizrak-http](https://github.com/legiz-ru/prizrak-http). Those contributions remain
the work of their respective authors. Source references are retained with the
relevant changes; this project does not claim sole authorship of incorporated
code or ownership of the original projects, names or trademarks.

The core also includes third-party libraries and other components. Each retains
its applicable license, copyright notices and attribution requirements. The
top-level GPL license does not replace their individual license texts or remove
their notices. Original license and notice files are retained with the
corresponding source, including locally modified dependencies.

Each binary release includes the corresponding core source in
`custom-core-source.tar.gz` and dependency sources in `vendor.tar.gz`.
Modification information is recorded in `DOWNSTREAM.md` within the source
distribution. When redistributing, preserve the applicable licenses, notices
and source availability required by those licenses.

The software is provided without warranty, as described in the applicable
licenses.

# share serve

`share serve` turns your Mac into a one-file download link for devices on the same network. It is the fastest way to move something to a phone, a Windows laptop, or a colleague's machine when AirDrop is unavailable.

```
$ share serve ./build.dmg --once

  Serving build.dmg (312.4 MB)
  http://192.168.1.24:52913/k3v9x2m8qz1a/build.dmg  copied ✓
  also: http://Reys-MacBook.local:52913/k3v9x2m8qz1a/build.dmg

  █▀▀▀▀▀█ ▄▀ ▄▄ █▀▀▀▀▀█
  █ ███ █ █▄  ▀ █ ███ █
  …

Waiting for downloads for 10m 0s… (Ctrl-C to stop)
  ↓ 192.168.1.31 downloaded build.dmg (312.4 MB)
First download complete, 1 download.
```

## Behavior

- Folders and multiple items are zipped first (smart mode and `--exclude` apply).
- The server binds to all interfaces on a random free port (or `servePort` / `--port`).
- The advertised address is the first Wi-Fi/Ethernet IPv4 address, preferring private ranges; override with `--host`.
- Only `GET` and `HEAD` for the exact `/<token>/<filename>` path are served. `/<token>` redirects to the file. Everything else is `404`; other methods are `405`.
- Single byte ranges are supported so iOS Safari and download managers can resume. A download counts as complete once a client has received the whole file, even across several range requests.
- Responses carry `Content-Disposition: attachment`, `Cache-Control: no-store` and `X-Content-Type-Options: nosniff`.
- Stops on Ctrl-C or SIGTERM, after `--timeout` seconds (default 600; `0` disables), or after the first full download with `--once`. Temporary zips are deleted once at least one download completed.
- With `notify: true` each download posts a notification.
- `--json` prints the URL, port, file and size as JSON before waiting, for scripts that want to hand the link to something else.

## Security model

- The 12-character random token makes the URL unguessable on a shared network, but anyone who sees the link can download the file while the server is running. Treat it like a link you pasted in chat.
- Transport is plain HTTP on the local network; do not use it across untrusted networks or for anything you would not send unencrypted over that network.
- There is no upload, no directory listing, and no way to reach other files.
- Nothing leaves the local network. No relay, no cloud.

## Troubleshooting

- **"no local network address found"**: connect to Wi-Fi or Ethernet, or pass `--host <ip>`.
- **The phone cannot open the link**: some networks (guest Wi-Fi, hotel networks) isolate clients from each other. Try a personal hotspot, or pass `--host` with the `.local` name.
- **Port is not available**: another process owns it. Omit `--port` for a random one.
- **macOS firewall prompt**: allow incoming connections for `share` (or your terminal) when asked.

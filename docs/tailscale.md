# Tailscale on nothotdog

Mastodon stays on the Raspberry Pi. Install Tailscale on the Ubuntu host so the
public edge can reach Caddy's published TCP ports 80 and 443. Do not advertise
subnet routes or enable Tailscale SSH or an exit node.

## Install the host client

On the Pi, use the official installer. Download and review it before running:

```sh
curl -fsSL https://tailscale.com/install.sh -o /tmp/install-tailscale.sh
less /tmp/install-tailscale.sh
sudo sh /tmp/install-tailscale.sh
sudo systemctl enable --now tailscaled
```

The host package persists identity in `/var/lib/tailscale`. Keep that state across
updates; do not run `tailscale logout` as part of normal maintenance.

## Interactive registration through Headplane

The Headscale policy must define `tag:mastodon` and allow the edge to reach its
TCP ports 80 and 443. The infrastructure configuration also creates a dedicated
`mastodon` user.

```sh
sudo tailscale up \
  --login-server=https://headscale.levizitting.com \
  --hostname=nothotdog \
  --accept-dns=false \
  --accept-routes=false
```

Open the registration URL printed by the client. In Headplane at
`https://headscale.levizitting.com/admin`, use **Add device / Register Machine
Key** with that URL or authentication request ID and select the `mastodon` user.
After registration, assign `tag:mastodon` to the node using the dashboard's
administrator controls. Verify that the tag is applied, the device is not
ephemeral, and node expiry is disabled. An untagged device will not match the
Mastodon ingress ACL.

If the dashboard does not expose those controls, run these commands in the
Headscale container on the edge host. Replace `NODE_ID` with the ID from the
node list, not a pre-auth key ID:

```sh
# On the edge host:
cd /opt/infra-public-edge
docker compose exec headscale headscale nodes list
docker compose exec headscale headscale nodes tag --identifier NODE_ID --tags tag:mastodon
docker compose exec headscale headscale nodes expire --identifier NODE_ID --disable
docker compose exec headscale headscale nodes list
```

The `--disable` flag is essential on the `expire` command: without it, the command
expires the node immediately. These commands match Headscale 0.29.4.

## Optional tagged enrollment key

Instead of interactive registration, create a single-use, non-ephemeral key in
Headplane carrying `tag:mastodon`. A short key validity is sufficient. The
infrastructure-managed alternative stores a one-hour enrollment key in AWS SSM
at `/homelab/headscale/mastodon/nothotdog-auth-key`. Retrieve it immediately after
creation; it is not renewed automatically when it expires.

Avoid putting the key in shell history or committing it. On the Pi:

```sh
read -r -s -p 'Headscale enrollment key: ' AUTH_KEY; printf '\n'
sudo tailscale up \
  --login-server=https://headscale.levizitting.com \
  --hostname=nothotdog \
  --accept-dns=false \
  --accept-routes=false \
  --auth-key="$AUTH_KEY"
unset AUTH_KEY
```

A key's expiration limits when it can enroll a device. It does not expire a node
that has already enrolled. Headscale 0.29.4 exempts new tagged enrollment from
default node expiry. Adding a tag to an existing node does not clear its existing
expiry, so explicitly disable expiry after interactive registration.
Non-ephemeral registration prevents deletion merely because the Pi is offline.
Confirm all three properties in the dashboard or node list.

## Verify the private path

```sh
tailscale status
tailscale ip -4
```

The edge backend hostname is `nothotdog.headnet.levizitting.com`, not the old
WireGuard hostname `nothotdog.levizitting.com`. Verify the new name resolves from
the edge host and from Traefik's container network. Before certificate issuance,
check port 80 with `Host: social.sgf.dev`; expect Caddy's HTTPS redirect. After
issuance, use the Pi's tailnet IPv4 address in a certificate-validating test:

```sh
# On the edge host; replace PI_TAILNET_IP with the address reported above:
curl --fail --show-error --resolve social.sgf.dev:443:PI_TAILNET_IP https://social.sgf.dev/health
curl --fail --show-error --resolve social.sgf.dev:443:PI_TAILNET_IP https://social.sgf.dev/api/v1/streaming/health
```

No new home-router port forwarding is needed. The Pi establishes Tailscale
connectivity outbound. Any existing Pi firewall must allow the intended
Tailscale connections; Docker-published ports also need a Docker-aware firewall
review if access from the LAN should be restricted.

## Retire WireGuard separately

The existing `wg0` tunnel is a full-tunnel connection through Middleout, including
outbound internet traffic. Keep it during enrollment and ingress testing.

Only after the new public ingress is working, use an SSH session through the Pi's
LAN or Tailscale address to disable `wg-quick@wg0`. Do not make that change through
a session that depends on WireGuard. Verify LAN internet egress, federation,
SMTP, DNS, and Restic backups before shutting down Middleout. Verify Tailscale
reconnects after a reboot. Disabling WireGuard and public DNS changes are not
performed by this repository.

## References

- [Headscale 0.29.4 node expiry configuration](https://github.com/juanfont/headscale/blob/v0.29.4/config-example.yaml)
- [Headscale 0.29.4 node administration commands](https://github.com/juanfont/headscale/blob/v0.29.4/cmd/headscale/cli/nodes.go)

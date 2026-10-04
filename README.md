# SGF Devs Mastodon instance

[Social.sgf.dev](https://social.sgf.dev) runs on the Raspberry Pi `nothotdog`.
Caddy terminates TLS on the Pi and publishes host TCP ports 80 and 443. It
proxies `/api/v1/streaming*` to `streaming:4000`, including WebSocket connections,
and all other paths to `web:3000`. The backends no longer publish host ports
9998 and 9999.

Caddy joins only `external_network`. Postgres and Redis remain on the isolated
`internal_network`. Install and manage Tailscale separately on the Pi host, not
in Compose. Follow [Tailscale enrollment and expiry instructions](docs/tailscale.md).
If the public edge uses Tailscale to reach the Pi, allow only the required hosts
and ports in its policy and the host firewall.

## Prepare the edge before deployment

- Keep the existing `.env.production`, app images, database volumes, and Compose
  project name. Run from the existing deployment directory on `nothotdog` so
  Compose reuses its volumes. This change needs no migrations or database work.
- Check that host TCP ports 80 and 443 are free and that the public edge can
  reach them. Caddy needs outbound access to the certificate authority.
- Public DNS currently points at old Middleout. Starting Caddy alone will not
  make HTTP-01 validation work. Before requesting a certificate, arrange for
  public port 80 requests to `social.sgf.dev/.well-known/acme-challenge/*` to
  reach Caddy's port 80 on the Pi, preserving the Host header and path. This can
  be a challenge-only proxy through old Middleout while other traffic stays on
  the old route. Check both A and AAAA paths if both exist. An HTTP redirect or
  Cloudflare proxy must not prevent the challenge from reaching the Pi.
- If the challenge cannot reach the Pi until the edge/DNS switch, expect a TLS
  bootstrap outage. Make port 80 reachable at that switch and wait for Caddy to
  obtain a certificate before treating the HTTPS route as ready. Do not use
  `curl -k` to approve the cutover.

The existing Middleout route expects `nothotdog:9999` and `nothotdog:9998`.
Recreating the backends below removes those listeners immediately, so coordinate
that step with the edge change. This procedure does not promise zero downtime.
The new edge must forward TCP 443 to the Pi without terminating TLS if TLS is
to terminate on the Pi. Forward TCP 80 as well for HTTP-01 and HTTPS redirects.

## Deploy Caddy and the Compose change

On `nothotdog`, from the existing deployment directory with the existing
`.env.production`:

```sh
docker compose config --quiet
docker compose pull caddy
docker compose run --rm --no-deps caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
# Coordinate this step with the edge cutover. Existing db, redis and sidekiq stay running.
docker compose up -d --no-deps web streaming caddy
docker compose ps
docker compose logs --tail=100 caddy
```

The deployment command assumes the existing database, Redis, and Sidekiq are
already running. It only recreates changed services, does not pull new Mastodon
images, and runs no migration commands. Do not use `docker compose down -v`.

The read-only `Caddyfile` mount holds the routing configuration. Named volumes
`caddy_data` and `caddy_config` persist certificates, private keys, and Caddy
state across container recreation. Keep them during updates. Existing backup
and restore scripts are unchanged and do not include these new named volumes.

## Local checks and cutover

Check the backends inside their containers, since their host ports are gone:

```sh
docker compose exec -T web wget -qO- --proxy=off http://localhost:3000/health
docker compose exec -T streaming wget -qO- --proxy=off http://localhost:4000/api/v1/streaming/health
# Expect an HTTP-to-HTTPS redirect, not a backend health response.
curl --fail --head --resolve social.sgf.dev:80:127.0.0.1 http://social.sgf.dev/health
# After certificate issuance, both must return successful health responses.
curl --fail --show-error --resolve social.sgf.dev:443:127.0.0.1 https://social.sgf.dev/health
curl --fail --show-error --resolve social.sgf.dev:443:127.0.0.1 https://social.sgf.dev/api/v1/streaming/health
```

The HTTPS checks use the real hostname for SNI and certificate validation while
connecting to localhost. Confirm successful certificate issuance in Caddy logs
and run these checks at cutover. Then test both health URLs from outside the Pi
without `--resolve`, and check a logged-in client's streaming connection. A
successful localhost check does not prove that the public edge points to the Pi.
DNS caches, stale IPv6 routes, and existing WebSocket connections can delay or
interrupt the switch.

For optional continuity after the Pi certificate is ready, old Middleout can
temporarily proxy HTTPS to the Pi's Caddy, using `social.sgf.dev` for Host and TLS
SNI and validating its certificate. That temporary route is not configured here.
Rolling back the edge to ports 9998/9999 also requires restoring the old Compose
port mappings and recreating web and streaming; changing DNS alone is not enough.

Caddy's default reverse proxy handling does not trust incoming forwarded client
headers. No blanket `trusted_proxies` or Cloudflare header override is configured.
If Cloudflare or Middleout remains upstream, the app may see that proxy's address
rather than the original client IP. Configure client-IP trust only with a reviewed
proxy allowlist and an edge that strips spoofed headers.

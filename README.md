# Long-running i2pd with one-shot Tor reseeding

Use Docker Engine and the Compose plugin on Linux. The router keeps its identity and peer database in `appdata/var/lib/i2pd/`. Tor runs in a separate container during a reseed download and exits afterward.

## First run

Run these commands from the repo root. If this router is already running with a usable peer database, skip the first-run reseed. Back up its data directory before replacing the container.

```sh
docker compose run --build --rm --no-deps reseed &&
  docker compose up -d --build i2pd
```

The helper shows Tor's bootstrap progress and reports that it is still waiting every 15 seconds. After Tor reaches 100%, the helper uses HTTPS through Tor with remote DNS resolution to fetch a signed SU3 bundle. It saves the bundle at `appdata/reseed/i2pseeds.su3`. The `&&` starts the router only after the helper succeeds.

Watch the router log for the SU3 import and subsequent peer and tunnel activity.

```sh
docker compose logs -f i2pd
```

i2pd verifies the bundle signature against the packaged reseed certificates. The Compose health check only verifies that the local web console responds. Use the console at `http://127.0.0.1:7070/` from the Docker host to check peer and tunnel status. The console, SAM, and I2CP listen on all host interfaces. Restrict access to those ports at the host firewall.

## Browse and use IRC over SSH

The HTTP and SOCKS proxies bind to `127.0.0.1` on the Docker host, as do the default IRC tunnels. From your client device, replace `user@docker-host` with your SSH login and run:

```sh
ssh -N -o ExitOnForwardFailure=yes \
  -L 127.0.0.1:4444:127.0.0.1:4444 \
  -L 127.0.0.1:4445:127.0.0.1:4445 \
  -L 127.0.0.1:6668:127.0.0.1:6668 \
  -L 127.0.0.1:6669:127.0.0.1:6669 \
  user@docker-host
```

Keep the SSH session open. Set your browser's HTTP proxy to `127.0.0.1:4444`, use `127.0.0.1:4445` for SOCKS5 apps that resolve hostnames through the proxy, or point your IRC client at `127.0.0.1:6668` or `127.0.0.1:6669`. You can omit forwards for services you don't use.

## Restart and recovery

Docker restarts the router after a process exit or daemon restart. A router with a usable peer database starts from its saved state. If it needs to reseed, it reads the local bundle. The i2pd config leaves the network reseed lists empty, so a missing, outdated, or rejected bundle requires a fresh download through the helper. Normal I2P peer traffic uses the router's own network connections.

If a cold start fails to find peers, fetch a fresh bundle and restart i2pd. Keep the existing state directory to preserve the router identity.

```sh
docker compose run --build --rm --no-deps reseed &&
  docker compose restart i2pd
```

The helper tries `reseed-fr.i2pd.xyz`, `reseed2.i2p.net`, and `reseed.diva.exchange` through the same Tor client. These are [upstream i2pd defaults](https://github.com/PurpleI2P/i2pd/blob/openssl/libi2pd/Config.cpp). The default URLs include `?netid=2` and the helper sends the user agent described by the [I2P reseed protocol](https://www.i2p.net/en/docs/misc/reseed/#reseed-request-specification).

For a specific source, pass `-e 'RESEED_URL=https://…/i2pseeds.su3?netid=2'` before the `reseed` service name in `docker compose run`. Use an HTTPS endpoint whose signing certificate i2pd trusts. If Tor cannot bootstrap or every download fails, the helper exits with an error and preserves any existing bundle.

The [I2P router guide](https://www.i2p.net/en/docs/guides/router-console-config/) points to [CheckI2P](https://checki2p.com/) for manual reseed downloads. Open it in Tor Browser, use a listed SU3 download, and save the file as `appdata/reseed/i2pseeds.su3` before starting the router.

## Configuration

Edit `config/i2pd.conf` for router settings. Compose mounts it read-only, and the Dockerfile uses the same file as the standalone image default. After editing the config, run `docker compose up -d --force-recreate i2pd` to load it.

`config/tunnels.conf` and `config/subscriptions.txt` are defaults. The entrypoint copies them into `appdata/var/lib/i2pd/` if they are missing. Edit the copies under `appdata/var/lib/i2pd/` to change those settings for an existing router.

Back up `appdata/var/lib/i2pd/` and `config/i2pd.conf` before upgrades or host migrations. Keep the backup private because it contains router and tunnel keys. Refresh the reseed bundle when recovery calls for it.

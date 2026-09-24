# 🚪 caddy-front

A shared HTTPS front door for running **several Docker Compose projects on one small server** (a DigitalOcean
droplet, Hetzner, any Linux VPS), each in its own repo, without tangling their setups.

One Caddy container ([caddy-docker-proxy](https://github.com/lucaslorentz/caddy-docker-proxy)) owns port 443 and
every TLS certificate. Each project registers itself with **labels** on its own containers; this repo never changes
when a project is added or removed.

```
internet ──443──▶ caddy-front (Caddy, automatic HTTPS for every site)
                    │  docker network "proxy"   (the only thing projects share)
                    ├──▶ app1.example.com        → project-1 web:80
                    └──▶ app2.example.com, <ip>  → project-2 app:3000
```

- **HTTPS only.** Nothing listens on port 80, so no plain HTTP is ever served.
- **Certificates come from Let's Encrypt** and renew automatically. They use the 6-day `shortlived` profile, which is the only profile Let's Encrypt issues **IP-address** certificates under, so `https://<server-ip>` works too. Validation runs over port 443 (TLS-ALPN).
- **`DEFAULT_SNI`.** When a browser connects by IP it sends no server name, so this tells Caddy which certificate to use.

## 1. Server setup (once)

Any x86_64 Linux server with a public IP works. 1 GB RAM plus swap is enough for a couple of small apps.
The commands below are for Ubuntu, run as root:

```bash
# Swap: a safety net for small servers
fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile \
  && echo '/swapfile none swap sw 0 0' >> /etc/fstab

# Firewall: SSH + HTTPS only
ufw allow OpenSSH && ufw allow 443/tcp && ufw allow 443/udp && ufw --force enable

# Docker (official install script)
curl -fsSL https://get.docker.com | sh
```

> Docker's published ports bypass `ufw`. Only this proxy should publish ports; projects must not.

## 2. Deploy the proxy

On your computer, in this repo:

```bash
cp .env.example .env                       # set VPS_TARGET=root@<server-ip>
ssh root@<server-ip> "mkdir -p caddy-front && echo DEFAULT_SNI=<server-ip> > caddy-front/.env"
make deploy                                 # copies docker-compose.yml, pulls, starts, waits until healthy
make logs                                   # recent proxy logs
```

`make deploy -- root@<other-ip>` overrides the target. The proxy creates the shared `proxy` Docker network.

## 3. Add a project

1. **DNS:** add an `A` record for the hostname pointing at the server. On Cloudflare, use **DNS only** (grey cloud), because the proxy has to reach Let's Encrypt directly.
2. **Compose:** on the project's container that serves HTTP, join the `proxy` network and add labels. A separate VPS-only file works well, for example a `docker-compose.vps.yml` enabled with `COMPOSE_FILE=docker-compose.yml:docker-compose.vps.yml` in the server `.env`:

   ```yaml
   services:
     web:
       networks: [default, proxy]
       labels:
         caddy: app.example.com                # site address(es), comma-separated; may include the server IP
         caddy.reverse_proxy: "{{upstreams 80}}" # the container's internal HTTP port

   networks:
     proxy:
       external: true
   ```

3. **Deploy the project** (`docker compose up -d`). The proxy picks up the labels within seconds and gets the certificate by itself, so no proxy redeploy is needed.

Rules for projects:
- **Don't publish ports** (`ports:`). The proxy reaches containers over the `proxy` network.
- **Only the public-facing container joins `proxy`.** Keep databases on the project's default network.
- **Use unique service names across projects on the `proxy` network** (for example `web`, `app`, `blog`). Docker DNS resolves service names on every network a container is attached to.
- **Serve plain HTTP inside the container.** TLS terminates at the proxy.

## Notes

- **Pinned image.** It's the `ci-alpine` tag, pinned by digest, because it bundles Caddy 2.11.4, the first version that can get IP-address certificates (the `2.12-alpine` release still has 2.11.3). Switch to a release tag once one ships Caddy ≥ 2.11.4.
- **Never delete the `caddy_data` volume.** Re-issuing certificates is rate-limited, to 5 per week for the same IP or name set.
- **Debugging.** See the generated Caddyfile with `docker exec caddy-front-caddy-1 cat /config/caddy/Caddyfile.autosave`.
- **Moving an existing Caddy setup here.** Copy its data volume into this one before the first start, so certificates aren't re-issued:
  ```bash
  docker volume create caddy-front_caddy_data
  docker run --rm -v <old>_caddy_data:/from -v caddy-front_caddy_data:/to alpine cp -a /from/. /to/
  ```

## License

MIT

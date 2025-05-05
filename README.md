# Nextcloud One-Shot Deployment

## Overview
`setup_nextcloud.sh` installs Docker + Compose, issues a Let’s Encrypt certificate and deploys a hardened Nextcloud stack behind Nginx in one run.  
After completion visit **https://<your-domain>** with the admin account you entered; **Settings → Administration → Overview** should show **no warnings**.

---

## What the script does

1. Installs **Docker Engine** and the **docker compose** plugin.  
2. Creates `/opt/nextcloud` containing  
   - **`.env`** – random secrets for MariaDB & Redis.  
   - **`docker-compose.yml`** – MariaDB 10.9, Redis, Nextcloud, Nginx.  
   - **`nginx.conf`** – HTTP→HTTPS redirect, HSTS, proper proxy headers/timeouts.  
3. Pulls images, starts DB + Redis, then Nextcloud.  
4. Runs `occ maintenance:install` with the admin credentials you supplied.  
5. Removes first-run wizard, empties skeleton, sets **Russian** as default language, `maintenance_window_start 03:00`, and correct `trusted_proxies`.  
6. Adds missing DB indices & performs expensive repairs.  
7. Issues a Let’s Encrypt certificate (stand-alone Certbot) and reloads Nginx.

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| **Ubuntu 20.04+** | Run script as **root** |
| Public DNS **A/AAAA** record | Points to this server |
| Open ports | 80 TCP, 443 TCP, 3478 TCP/UDP (TURN) |

---

## Usage

```bash
chmod +x setup_nextcloud.sh
sudo ./setup_nextcloud.sh
```

The script prompts for:

* **Domain** (FQDN)  
* **Admin e-mail** (Let’s Encrypt)  
* **Nextcloud admin user / password**

Run time ≈ 2‑5 minutes on a fresh VM.

---

## Resulting structure

```
/opt/nextcloud/
 ├─ .env                  # secrets
 ├─ docker-compose.yml
 ├─ nginx.conf
 └─ certbot/www/          # ACME HTTP‑01 dir
```

---

## Customisation

* Change PHP limits → edit `app` env or use `occ config:system:set`.
* Deploy Talk **HPB** → add separate TURN/Janus stack, fill Talk settings.
* Upgrade Nextcloud → `docker compose pull && docker compose up -d`.

---

## Backup

```bash
docker compose down
tar czf nextcloud_volumes.tgz   /var/lib/docker/volumes/nextcloud_db_data   /var/lib/docker/volumes/nextcloud_nextcloud_data
docker compose up -d
```

---

## Uninstall

```bash
cd /opt/nextcloud
docker compose down --volumes
rm -rf /opt/nextcloud
apt purge docker-ce docker-ce-cli containerd.io
```

---

## License
MIT — use at your own risk.

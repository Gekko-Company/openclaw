# OpenClaw in Docker (VPS)

Run the OpenClaw Gateway in Docker on a VPS. Image: **Harbor** `harbor.gekko.company/openclaw/openclaw:latest`.

**Requirements:** Docker, Linux (e.g. Ubuntu/Debian). No source code needed on the VPS.

---

## 1. On the VPS: create dirs and run the gateway

```bash
sudo mkdir -p /opt/openclaw/config /opt/openclaw/workspace
sudo chown -R 1000:1000 /opt/openclaw
```

```bash
docker login harbor.gekko.company
docker pull harbor.gekko.company/openclaw/openclaw:latest

export OPENCLAW_GATEWAY_TOKEN="$(openssl rand -hex 32)"
echo "Save this token: $OPENCLAW_GATEWAY_TOKEN"

docker run -d \
  -p 18789:18789 \
  -v /opt/openclaw/config:/home/node/.openclaw \
  -v /opt/openclaw/workspace:/home/node/.openclaw/workspace \
  -e OPENCLAW_GATEWAY_TOKEN="$OPENCLAW_GATEWAY_TOKEN" \
  --name openclaw-gateway \
  --restart unless-stopped \
  harbor.gekko.company/openclaw/openclaw:latest
```

Open **http://&lt;VPS_IP&gt;:18789/** in a browser and paste the token in **Settings**.

---

## 2. First-time setup (if UI shows "Disconnected" or "No agent")

Run onboarding once so the gateway has config and an agent. Use the **same** token as above.

```bash
docker stop openclaw-gateway

docker run --rm -it \
  -v /opt/openclaw/config:/home/node/.openclaw \
  -v /opt/openclaw/workspace:/home/node/.openclaw/workspace \
  -e OPENCLAW_GATEWAY_TOKEN="$OPENCLAW_GATEWAY_TOKEN" \
  harbor.gekko.company/openclaw/openclaw:latest \
  node openclaw.mjs onboard --no-install-daemon --flow quickstart
```

When asked, choose bind **lan** and auth **token**; paste the same token. Then:

```bash
docker start openclaw-gateway
```

---

## 3. Common commands

**Logs**

```bash
docker logs -f openclaw-gateway
```

**List / approve devices (pairing)** — run *inside* the gateway container. You must pass `--url ws://127.0.0.1:18789` and `--token` (same token you used to start the container):

```bash
docker exec -it openclaw-gateway node openclaw.mjs devices list --url ws://127.0.0.1:18789 --token "31b2549dcbe6ba0f693da0c9e805aa700a5c225647b96fe910bfc8931a828867"
docker exec -it openclaw-gateway node openclaw.mjs devices approve ab8ad28d-4418-40b9-8eeb-712fb26a102a --url ws://127.0.0.1:18789 --token "31b2549dcbe6ba0f693da0c9e805aa700a5c225647b96fe910bfc8931a828867"
```

Replace `YOUR_GATEWAY_TOKEN` with the **exact** token the gateway was started with. If you no longer have it, read `gateway.auth.token` from `/opt/openclaw/config/openclaw.json` on the VPS.

**Any other CLI** (agents, config, channels, doctor) — use a one-off container with the same mounts:

```bash
docker run --rm -it \
  -v /opt/openclaw/config:/home/node/.openclaw \
  -v /opt/openclaw/workspace:/home/node/.openclaw/workspace \
  harbor.gekko.company/openclaw/openclaw:latest \
  node openclaw.mjs <command> [args...]
```

Example: `node openclaw.mjs agents list` or `node openclaw.mjs config set gateway.bind lan`.

---

## Recipes (blog / templates)

If you want the agent to use **recipes** (e.g. “thought leadership blog”) instead of writing from scratch, the **recipe-inject** plugin must be configured and given a directory of recipe YAML files.

**1. Create a recipes directory** inside your mounted config (so the container can read it):

```bash
sudo mkdir -p /opt/openclaw/config/recipes
sudo chown 1000:1000 /opt/openclaw/config/recipes
```

**2. Add at least one recipe file** (YAML with `id`, `triggers`, and `prompt`). The filename must match the `id` inside the file (e.g. `thought-leadership-blog.yaml`). If you have the repo:

```bash
cp docs/recipes/example-thought-leadership-blog.yaml /opt/openclaw/config/recipes/thought-leadership-blog.yaml
sudo chown 1000:1000 /opt/openclaw/config/recipes/thought-leadership-blog.yaml
```

If you don’t have the repo, create `/opt/openclaw/config/recipes/thought-leadership-blog.yaml` with content like:

```yaml
id: thought-leadership-blog
name: "Thought leadership blog post"
triggers: ["blog", "write a blog", "blog post", "thought leadership", "write an article"]
prompt: |
  Follow this recipe for a thought leadership blog post:
  1. Open with a clear point of view or question that hooks the reader.
  2. Use 3–5 short sections with subheadings; one idea per section.
  3. Include at least one concrete example or data point per section.
  4. End with a call to action or a reflection that ties back to the opening.
  5. Keep tone professional but conversational; target 800–1200 words.
```

**3. Enable the plugin and set the recipe dir** in OpenClaw config. Edit `/opt/openclaw/config/openclaw.json`. **`plugins` must be at the root** of the JSON (same level as `gateway`, `agents`, etc.), **not** inside `gateway`. Example shape:

```json
{
  "gateway": { "bind": "lan", "auth": { "token": "…" } },
  "plugins": {
    "entries": {
      "recipe-inject": {
        "enabled": true,
        "config": {
          "recipeDir": "/home/node/.openclaw/recipes"
        }
      }
    }
  }
}
```

If you add only the `plugins` block, merge it into your existing root object; do not put it under `"gateway"` or you will get “gateway: Unrecognized key: plugins”. Use exactly `"/home/node/.openclaw/recipes"` for `recipeDir`. In the container that path is your mounted config plus `recipes`; on the host create `/opt/openclaw/config/recipes` first and set ownership to 1000:1000.

**4. Restart the gateway:** `docker restart openclaw-gateway`.

After this, prompts like “write a blog” or “write a thought leadership article” should match the recipe and the agent will receive the recipe text as context. If it still doesn’t use a recipe, check gateway logs for `recipe-inject:` messages (e.g. “recipe dir …”, “matched recipe …”) and confirm trigger words in your prompt match one of the recipe’s `triggers`.

---

## 4. Troubleshooting

| Problem | Fix |
|--------|-----|
| `EACCES` writing config/workspace | `sudo chown -R 1000:1000 /opt/openclaw` |
| "gateway token missing" (1008) | Set `gateway.remote.token` in config to the same value as `gateway.auth.token` (the token the gateway expects). Use a one-off container: `node openclaw.mjs config set gateway.remote.token "YOUR_TOKEN"`. |
| **"gateway token mismatch"** | The token you pass with `--token` (or in config as `gateway.remote.token`) must **exactly** match the token the gateway was started with (`OPENCLAW_GATEWAY_TOKEN`). If you no longer have it, read it from the mounted config: `gateway.auth.token` in `/opt/openclaw/config/openclaw.json`. Then use that same value for `--token` and set `gateway.remote.token` to it. |
| "pairing required" on `devices list` | Use `--url ws://127.0.0.1:18789` and `--token` with the **exact** gateway token (see above). |
| "gateway url override requires explicit credentials" | When using `--url` you must also pass `--token` (same token as when you started the container). |
| **"Proxy headers detected from untrusted address"** | You run behind a reverse proxy (nginx, etc.). Set `gateway.trustedProxies` to the proxy IP so local client detection works. In a one-off container: `node openclaw.mjs config set gateway.trustedProxies '["127.0.0.1"]'` (if proxy is on same host) or `'["172.17.0.1"]'` (Docker host as seen from container). Then `docker restart openclaw-gateway`. |
| Control UI not reachable | Set `gateway.bind` to `lan` and restart: `docker restart openclaw-gateway`. |
| Container exits | `docker logs openclaw-gateway`; ensure token and mounts are correct. |
| **Agent doesn’t use recipes** (e.g. “writes blog by itself”) | Configure the recipe-inject plugin and add recipe YAML files; see [Recipes (blog / templates)](#recipes-blog--templates). Ensure `plugins.entries.recipe-inject.config.recipeDir` is set to `/home/node/.openclaw/recipes`, recipe files exist there (filename = `id` + `.yaml`), and your prompt contains a trigger word (e.g. “write a blog”, “blog”). |
| **"gateway: Unrecognized key: plugins"** | You put `plugins` **inside** `gateway`. Move `plugins` to the **root** of `openclaw.json` (same level as `gateway`, not under it). See the example in [Recipes](#recipes-blog--templates). |
| **recipe-inject shows "error" / can't find recipeDir** | (1) **Config:** Set `plugins.entries.recipe-inject.config.recipeDir` to exactly `"/home/node/.openclaw/recipes"` (root-level `plugins`, not under `gateway`). (2) **Directory:** On the host create `/opt/openclaw/config/recipes`, run `chown 1000:1000 /opt/openclaw/config/recipes`, and add at least one `.yaml` recipe file. (3) Restart the gateway. To see the exact error: `node openclaw.mjs plugins info recipe-inject` in a one-off container. |

**Security:** Use a strong token; restrict port 18789 or use an SSH tunnel (`ssh -L 18789:127.0.0.1:18789 user@vps`).

---

## Build and push image (Windows)

From the repo root in PowerShell:

```powershell
.\deploy-harbor.ps1
```

Builds with `Dockerfile.vps`, tags `harbor.gekko.company/openclaw/openclaw:latest`, pushes to Harbor. Optional: `-ImageTag "1.0.0"`, `-RunLocally` to run the container locally after push.

---

## Run with Compose or build from repo (optional)

If you have the **repo on the VPS**: create dirs and `.env` (e.g. `OPENCLAW_GATEWAY_TOKEN`, `OPENCLAW_CONFIG_DIR`, `OPENCLAW_WORKSPACE_DIR`), then:

```bash
docker compose -f docker-compose.vps.yml build
docker compose -f docker-compose.vps.yml up -d
```

Devices list/approve: `docker compose -f docker-compose.vps.yml exec openclaw-gateway node openclaw.mjs devices list --url ws://127.0.0.1:18789` (and same for `devices approve`).

If you build the image yourself (no Harbor): `docker build -f Dockerfile.vps -t openclaw:vps .` then run as in section 1 with image `openclaw:vps`.

---

**Files:** `Dockerfile.vps`, `docker-compose.vps.yml`, `deploy-harbor.ps1`. More: [docs.openclaw.ai](https://docs.openclaw.ai).

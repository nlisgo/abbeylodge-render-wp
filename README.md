# Abbey Lodge WordPress Bootstrap

This repo builds a single Docker image that runs:

- the latest stable `wordpress` official image as the base
- Apache for HTTP
- a local MariaDB server inside the same container so WordPress has a MySQL-compatible database immediately

This is a bootstrap setup to get Render deployment working quickly. It is not the end-state architecture. The intended next step is to switch `WORDPRESS_DB_HOST` to an external managed database and remove the embedded database server from the image.

## What is included

- `Dockerfile` based on the official `wordpress:latest` image
- `docker/start-wordpress.sh` to start MySQL, prepare persistent storage, and then hand off to the official WordPress entrypoint
- `.github/workflows/build-and-push.yml` to build and push to `ghcr.io` on every push
- `render.yaml` for an image-backed Render web service

## How the container works

- If `WORDPRESS_DB_HOST` is `127.0.0.1:3306` or `localhost:3306`, the container starts the embedded database server.
- If `WORDPRESS_DB_HOST` points somewhere else, the container skips local MySQL startup so you can move to an external database later without changing the image.
- WordPress uploads, themes, plugins, and the MySQL data directory are stored under `APP_DATA_DIR` so they can live on one Render persistent disk.

## Create the GitHub repo

If you use GitHub CLI and are already authenticated:

```bash
gh repo create abbeylodge-render-wp --public --source=. --remote=origin --push
```

If you create the repo in the GitHub UI instead, add the remote and push:

```bash
git remote add origin git@github.com:<your-user-or-org>/abbeylodge-render-wp.git
git push -u origin main
```

## GitHub Actions and GHCR

The workflow pushes these tags:

- branch tags like `main`
- commit tags like `sha-<commit>`
- `latest` on the default branch

Important:

1. GitHub says the first container package published to GHCR is private by default.
2. After the first workflow run, go to the package in GitHub and set its visibility to `public`.
3. Keep the repository public as well.

The workflow uses `${{ secrets.GITHUB_TOKEN }}` and `packages: write`, which GitHub documents as the recommended way to publish a package linked to the repository.

## Render setup

Render docs currently state:

- image-backed services do not auto-redeploy when a new registry image is pushed
- a deploy hook is the supported way to trigger a new deploy from GitHub Actions
- persistent disks require a paid service

To wire Render up:

1. Update `render.yaml` and replace `REPLACE_WITH_GITHUB_OWNER` with your GitHub username or org.
2. Push the repo to GitHub.
3. Let GitHub Actions publish the first image to `ghcr.io`.
4. Make the GHCR package public, or add a GHCR credential in Render if you want to keep it private.
5. In Render, create a new Blueprint or web service using this repo.
6. After the service exists, copy its deploy hook URL from Render.
7. Add that hook in GitHub as the `RENDER_DEPLOY_HOOK_URL` repository secret.

After that, every push will:

- build and push a new image to `ghcr.io`
- trigger a Render deploy from the default branch

## Render notes

- The included `render.yaml` uses `starter` because Render only supports persistent disks on paid services.
- This setup keeps both WordPress content and the embedded DB on the same mounted disk at `/var/data`.
- Render will stop the existing instance before starting the new one when a disk is attached, so deploys are not zero-downtime in this setup.

## Sources

- WordPress official image: https://hub.docker.com/_/wordpress
- WordPress Docker source: https://github.com/docker-library/wordpress
- GitHub Actions publishing docs: https://docs.github.com/en/actions/tutorials/publish-packages/publish-docker-images
- GitHub Container registry docs: https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry
- Render deploy hooks: https://render.com/docs/deploy-hooks
- Render prebuilt images: https://render.com/docs/deploying-an-image
- Render Blueprint spec: https://render.com/docs/blueprint-spec
- Render persistent disks: https://render.com/docs/disks

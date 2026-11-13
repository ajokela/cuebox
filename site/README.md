# Cuebox website

Source for **https://cuebox.gd**. Buildless HTML, CSS and JavaScript; original
SVG workshop illustration; self-hosted Space Grotesk and IBM Plex Mono fonts.
The illustration is a small website interaction. The separate playable sample
is the real Godot export of The Last Signal, loaded only on request.

## Build and preview

Requires Python 3, Godot 4.7.2 and its matching Web export templates:

```sh
python3 site/tools/draw_workshop.py  # only needed after changing the drawing
python3 site/tools/build.py
python3 -m http.server 8767 --bind 127.0.0.1 --directory build/website/dist
```

Open `http://127.0.0.1:8767/`. The build copies only explicitly selected website
files and exports from an isolated copy of `engine/`, `examples/`, and the
project configuration. It does not export a host game or the website source.
It also writes the installed Godot engine's license and third-party notices.
The sample's saves and preferences stay in browser IndexedDB.

The social card is `assets/social.png`; render `tools/social.html` at 1200×630
to update its composition of the site's typography and original workshop SVG.
Font licenses are in `assets/`.
All other website source and original art use the repository's MIT license.

## AWS hosting

`infra/site.yaml` owns a private S3 bucket (all four public-access blocks, bucket
owner enforced, encryption and versioning), a CloudFront distribution with
signed Origin Access Control, an ACM certificate, routing and security headers,
and apex/`www` Route53 aliases. It uses the S3 REST endpoint, not website hosting.
Only the named distribution can read the bucket publicly via CloudFront.
The bucket is retained if the stack is deleted; old versions expire after 90 days.

Deploy the stack in **us-east-1** so CloudFront can use its certificate. Supply
the public hosted-zone ID at deploy time; account details stay out of source.
For the first deployment, provision with `PublishDNS=false`, upload and verify
the CloudFront hostname, then update to `PublishDNS=true`:

```sh
aws cloudformation deploy --region us-east-1 --stack-name cuebox-website \
  --template-file site/infra/site.yaml \
  --parameter-overrides HostedZoneId=YOUR_ZONE_ID PublishDNS=false
python3 site/tools/upload.py
# Verify the distribution hostname from build/website/deployment.json.
aws cloudformation deploy --region us-east-1 --stack-name cuebox-website \
  --template-file site/infra/site.yaml \
  --parameter-overrides HostedZoneId=YOUR_ZONE_ID PublishDNS=true
```

For content updates, build, inspect, and run `upload.py` again. The upload reads
bucket/distribution identifiers from this stack's outputs. WASM and PCK payloads
are precompressed and served at their ordinary URLs with correct MIME types
and `Content-Encoding: gzip`. HTML requires revalidation. An invalidation is
created for each upload. Deployment state is saved only under ignored `build/`.

Before publishing, check desktop and narrow layouts, keyboard navigation,
workshop interactions/reset, the copy button, all links, and the real sample
from title through its ending. Confirm the game isn't downloaded before Play.
After publishing, check HTTPS, `www` redirect, the custom 404, compressed game
assets, and an anonymous S3 request returning 403.

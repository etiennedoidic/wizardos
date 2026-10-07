# WizardOS

Not an operating system. A layout and later a PWA on top of
[friendly-hosting](friendly-hosting/README.md).

## First-time owner

On the Mac that will host (or on a laptop while you develop):

```
./wizard-init.sh
```

It asks whether pages should be private (Tailscale only), public, or both.
Then it:

1. Writes `~/wizard/{app,data,seeds,blobs,config}` and puts the Wall in
   the existing public tree (`~/www/wall`).
2. Calls friendly-hosting `owner-init.sh` (users, Tailscale, Serve).
3. If you chose public or both, calls `enable-public-www.sh`.

It refuses to create a second owner instance if another macOS user on this
Mac already has `~/wizard/config/instance.json` with `"role": "owner"`.

`wizard-init.sh` does not itself run `sysadminctl`, `tailscale up`, ACL
writes, Funnel, cloudflared, or `pmset`. Those stay in friendly-hosting.

## Layout only

If the unix user already exists (a renter with SSH, or you re-running):

```
./scripts/wizard-layout.sh --role owner
./scripts/wizard-layout.sh --role renter
```

## Hosting without WizardOS

Use `friendly-hosting/` on its own. Defaults there are `~/srv` (private)
and `~/www` (public). No Wall, no seeds.

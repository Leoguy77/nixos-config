# Plan: `pi-packages.nix` — a Nix-native flake for pi.dev packages (Garnix-cached)

## Goal
Publish a public Nix flake that lets anyone install **pi native packages** (from
the pi.dev / npm `pi-package` catalog) declaratively and reproducibly, with a
**free binary cache via Garnix**. No nixpkgs merges, no manual hashing, no paid
services.

---

## Key findings (validated during research)

1. **pi packages are npm packages.** The pi.dev catalog is a view over the npm
   registry. Packages are discoverable via the `pi-package` keyword.
   - Search: `registry.npmjs.org/-/v1/search?text=keywords:pi-package` → **~4,893** packages (JSON).
   - Per-package metadata `registry.npmjs.org/<name>` gives:
     - `dist.tarball` (download URL)
     - `dist.integrity` = `sha512-…` → **already Nix SRI format** (drop into `hash =`)
     - `pi` manifest (`extensions`/`skills`/`prompts`/`themes`)
     - `dependencies` (to decide build tier)
   - ⇒ Registry generation needs **zero manual hashing / no TOFU**.

2. **A pi package bundles 4 resource types + npm deps:** `extensions`, `skills`,
   `prompts` (templates), `themes`.

3. **Local-path packages** are loaded by pi **without** `npm install` (unlike
   `npm:`/`git:` sources). So a store path that already contains files (+ `node_modules`
   if needed) is loaded directly → pure, offline, reproducible.

4. **Two build tiers:**
   - **Tier A — pure `.ts` / peerDeps-only** (large fraction): no real npm deps →
     trivial `runCommand` copy of the tarball. No lockfile, no `npmDepsHash`.
   - **Tier B — has `dependencies`**: needs `node_modules` → `buildNpmPackage`
     (+ `importNpmLock` if tarball ships a lockfile, else `prefetch-npm-deps`).
   - Peer deps on pi core (`@earendil-works/pi-*`, `typebox`) must **not** be bundled;
     pi provides them at load time.

5. **Caching is content-addressed** → can only pre-warm packages known at CI time.
   The generated registry IS that known set. Garnix builds flake outputs and serves
   `https://cache.garnix.io` free for public repos.

---

## Deliverables (repo layout of the new flake)

```
pi-packages.nix/
├── flake.nix                 # inputs, outputs, nixConfig (garnix substituter)
├── lib/
│   └── mkPiPackage.nix       # 3-tier builder (copy | buildNpmPackage)
├── registry/
│   ├── registry.json         # GENERATED: name, version, tarball, sha512, tier, manifest
│   └── generate.mjs          # crawler: npm registry → registry.json
├── modules/
│   ├── nixos.nix             # programs.pi.coding-agent.packages option
│   └── home-manager.nix
├── packages/                 # exposed derivations per system (+ aggregate)
├── .github/workflows/
│   └── update-registry.yml   # scheduled bot PR regenerating registry.json
├── garnix.yaml               # tell Garnix what to build/cache
└── README.md
```

---

## Component design

### 1. Registry generator (`registry/generate.mjs`)
- Query `keywords:pi-package` search endpoint, paginate to cover all ~4,893.
- For each name, fetch metadata; extract latest `version`, `dist.tarball`,
  `dist.integrity`, `pi` manifest, `dependencies`, `keywords`, download count.
- Classify tier: `A` if `dependencies` empty/only pi-core peers, else `B`.
- Emit `registry.json` (data only — URLs + hashes + metadata, no code import).
- Deterministic + reviewable; committed via bot PR.

### 2. `lib/mkPiPackage.nix`
- Input: one registry entry (or a raw `{ name, tarball, hash, tier, deps }`).
- Tier A: `runCommand` → unpack tarball → `$out`.
- Tier B: `buildNpmPackage` with `src = fetchurl { url; hash; }`,
  `importNpmLock` when lockfile present, `dontNpmBuild = true`, copy to `$out`
  including `node_modules`.
- Output: store path suitable for `settings.packages = [ "${pkg}" ]`.

### 3. Module option `programs.pi.coding-agent.packages`
- Accepts: catalog names (`"pi-web-access"`), raw source strings, or `mkPiPackage`
  derivations.
- Resolves names → registry entry → `mkPiPackage` → store path.
- Writes resolved store paths into pi `settings.packages`.
- Complements (does not replace) pi.nix's `extensions`/`skills`/`themes` options.
- Decide: extend `lukasl-dev/pi.nix` via overlay/PR, or ship standalone module.

### 4. Flake outputs
- `packages.<system>.<pkgName>` for each registry entry (lazy).
- `packages.<system>.all-tierA` aggregate (cheap; build+cache eagerly).
- `lib.mkPiPackage`, `overlays.default`, `nixosModules.default`, `homeModules.default`.
- `nixConfig.extra-substituters = [ "https://cache.garnix.io" ]` + trusted key.

### 5. Garnix build/cache (`garnix.yaml`)
- Configure Garnix to build the aggregate targets (Tier A eagerly; popular Tier B
  ranked by download count) across `x86_64-linux` / `aarch64-*`.
- Garnix auto-serves `https://cache.garnix.io` — no tokens, no workflow to push.
- Consumers add the substituter (or inherit via flake `nixConfig`).

### 6. Registry refresh automation (`.github/workflows/update-registry.yml`)
- `on: schedule` (e.g. daily) + manual dispatch.
- Run `generate.mjs`; if `registry.json` changed, open a bot PR.
- Merge → Garnix rebuilds deltas → cache re-warmed. No hashing step ever.

---

## Phased execution

- **Phase 0 — spike/validation**
  - Confirm pi loads a pre-populated local-path package **without** running `npm install`
    (the purity assumption). Test with one Tier A + one Tier B package.
- **Phase 1 — Tier A end-to-end**
  - `generate.mjs` (Tier A only) → `mkPiPackage` copy path → 5–10 sample packages →
    module option → Garnix building + caching. Prove the full loop cheaply.
- **Phase 2 — Tier B (node_modules)**
  - Add `buildNpmPackage` + `importNpmLock`/`prefetch-npm-deps`; handle peerDeps
    exclusion; test the highest-download packages.
- **Phase 3 — full registry + scale controls**
  - Generate all ~4,893; shard/rank builds by download count; cache-check before build;
    scheduled bot-PR refresh.
- **Phase 4 — publish & docs**
  - README (usage, security warning, substituter setup), decide standalone vs. pi.nix
    integration, tag a release.

---

## Risks & mitigations
| Risk | Mitigation |
|---|---|
| Purity assumption (pi runs `npm install` on local path) | Phase 0 spike before building anything else |
| Scale: 4,893 × N systems CI cost | Tier A eager; Tier B ranked by downloads; cache-check before build |
| Tier B lockfile/`npmDepsHash` | `importNpmLock` when tarball ships lockfile; else `prefetch-npm-deps` |
| Supply-chain (packages run with full system access) | Registry = data only; nothing auto-imported; users opt in per package; security note in README |
| Garnix control/limits | Keep optional Cloudflare R2 (`nix copy`, free egress) push as fallback |
| npm-only coverage | Rare git-only packages → `fetchFromGitHub` + lockfile path |

## Decisions (confirmed)
1. **Standalone flake** (not upstreaming to `lukasl-dev/pi.nix`).
2. **Repo name: `pi-packages.nix`** → `github:Leoguy77/pi-packages.nix`.
3. **Cache all Tier A eagerly** (full registry, cheap builds).
4. **Both Garnix + R2 fallback** (Garnix primary, R2 for independence/scale).
```

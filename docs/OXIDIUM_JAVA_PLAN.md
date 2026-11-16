# Oxidium: Java Edition integration plan

> Status: **design proposal, not implemented**. Based on the Oxidium planning handoff of 2026-11-16. This plan is independent from the upstream Horizon roadmap.

## Goal and limits

Keep the existing Rust-native Horizon-derived game and launcher functional while adding **a separate Java Edition instance runner**. Import existing installations owned by the player from Prism, Freesm, Halky, Shattered Prism, MultiMC-compatible layouts and, later, other launchers. Both game engines appear in Oxidium's instance list but have independent runtimes and mod systems.

**The Rust client cannot execute Java mod JARs.** Never represent native Rust mods or data-only mod ports as a full Java mod loader.

The first integration path consumes **existing local game files**. Do not download, bundle or republish Minecraft client/server JARs, vanilla assets or vanilla libraries. Missing inputs must be reported in the UI. Do not bypass license or account ownership checks. Existing account handling should be evaluated before implementing anything new.

## Important repository facts

- Fork lineage: Horizon → Horizon-Free → Oxidium.
- Current AppImage workflow: `.github/workflows/oxidum-appimage.yml`; current packaged filename: `oxidum-linux-x86_64.AppImage`.
- Renaming the project does not rename embedded launcher identifiers, release assets, workflow references or the updater by itself.
- The launcher workspace is in `launcher/`, and the fork overlay is under `tools/fork/`.
- `ROADMAP.md` is an upstream-generated Horizon roadmap. Keep Oxidium-specific delivery plans in this document rather than changing upstream-generated sections.

## Modules and boundaries

1. **Prism-family discovery (read-only):** inspect XDG and Flatpak data locations plus explicit directories; recognize `instances/`, `instance.cfg`, `mmc-pack.json`, game folder, `libraries/`, `assets/`, and component metadata. Provide a preview and missing-file diagnostics. Do not modify origin installations during discovery.
2. **Instance storage:** retain Prism-compatible data on disk where practical; write Oxidium-only metadata separately as `oxidium.json`. Support reference mode (read origin) and adopted mode (copy into Oxidium control) after explicit confirmation. Prefer copies over links when unlinking or changing files could damage the source.
3. **Java runner:** construct classpath and JVM/game args from locally installed version and loader metadata; implement OS/architecture rules, natives, asset index, both modern `arguments` and legacy `minecraftArguments`. Never assume Prism component JSON equals Mojang version JSON.
4. **Java runtime resolution:** discover installed Javas from `JAVA_HOME`, system installations and launcher runtimes; choose a compatible major for each instance. Runtime downloads may be added separately with integrity checking.
5. **Mod loaders:** first import preinstalled Fabric and Quilt instances; install/update loaders only after tests establish expected metadata layout. Forge and NeoForge follow.
6. **Java mod management:** query Modrinth by loader/game version, verify SHA-512/SHA-1, resolve dependencies and keep an instance-local lockfile. Support `.mrpack` overrides, rollback and safe disable/remove. Do not run untrusted JARs during installation.
7. **UI:** use existing instance navigation; distinguish Java and Rust; give Java instances their own Mods, Modpacks, Java/Memory, Worlds and Logs views.
8. **Linux distribution:** maintain the fork's AppImage workflow and optional per-instance dedicated GPU, GameMode and MangoHud configuration. Avoid a second `.desktop` registration under GearLever.

## Milestones and acceptance

| Phase | Deliverable | Acceptance check |
| --- | --- | --- |
| 0 | Baseline and architecture inventory | Read `AGENTS.md`, `CONTRIBUTING.md`, `launcher/` and `tools/fork/`; run the existing checks and record working entry points |
| 1 | Prism-family discovery | A synthetic fixture and a real opt-in directory are enumerated without any write |
| 2 | Vanilla Java launch | An already-installed Java instance starts, logs are visible, and missing files produce actionable errors |
| 3 | Fabric / Quilt and Java selection | Local preinstalled Fabric instance starts with the correct runtime |
| 4 | Modrinth management and `.mrpack` | install/update/remove/disable work; hash mismatch aborts cleanly |
| 5 | Forge / NeoForge / CurseForge | Each loader validated separately, API and redistributability rules respected |
| 6 | Windows support | paths, subprocesses and packaging covered by platform tests |
| 7 | Export / migrations / legacy versions | Prism-compatible export round-trip and migration tests pass |

## AppImage / release migration: Oxidum → Oxidium

This is separate from the README correction and needs its own tested PR:

- Change built artifact names, package metadata and launcher desktop identifiers together.
- Update embedded update URLs, release asset lookup, version tracking and checksum verification.
- Do not create a new AppImage on every launch; atomically replace the prior managed file with rollback and permissions preserved.
- When GearLever manages the AppImage, detect and respect its managed path; avoid creating duplicate launchers or desktop files.
- Verify that an actual published release updates a previous release without breaking launcher state.
- Maintain a compatibility path for installations still named `oxidum-linux-x86_64.AppImage`.

## Safety and licensing

Prism-derived launchers have GPL-licensed code; do not copy their implementation into MIT code without an explicit licensing decision. File format interoperability can be implemented independently. Never commit Mojang files or prepared resources. Native Rust mods and Java JARs may execute third-party code at runtime; treat them as untrusted.

## Outstanding decisions

Reference vs adoption as import default; supported account flows; priority for NeoForge; CurseForge API credentials; legacy Minecraft versions; and how to handle Flatpak filesystem permissions.

## Status

This document is a technical plan. No Java runner, importer, integration tests or validated updated AppImage is delivered by this documentation change.

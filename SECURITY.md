# Security Policy

## Supported versions

Only the **latest release** gets fixes. Cape updates itself (Settings › Updates),
so staying current is one click.

## Reporting a vulnerability

Please **don't open a public issue** for a security problem. Report it privately
on GitHub instead: **Security › Report a vulnerability** on this repository
([direct link](https://github.com/timryadovouu/cape/security/advisories/new)).

Include what you found, how to reproduce it, and the Cape and macOS versions.
You'll get a reply within a few days; a confirmed issue is fixed in a release
and credited to you in the changelog, if you like.

## How releases are protected

- **Built in the open.** Every release is built by GitHub Actions from the
  tagged source; the build logs are public.
- **Signed.** Releases are signed with the project's own code-signing
  certificate (not notarized by Apple — see the README).
- **Verified on update.** The in-app updater installs a download only if it's
  signed by the same certificate as the running app; anything else is rejected.

## What Cape touches

Everything stays on your Mac — no accounts, no telemetry. Network use is limited
to the update check and download (GitHub Releases), Spotify cover images, and the
one-time dictation model download. Optional integrations write to files outside
Cape's own folder only when you turn them on: Claude Code hooks in
`~/.claude/settings.json` and one line in `~/.zshrc` for `cape done` — both
backed up first. The README's *Where data lives* and *Permissions* sections have
the details.

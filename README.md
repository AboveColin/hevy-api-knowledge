# hevy-api-knowledge

A Claude Code skill for working with the [Hevy](https://www.hevyapp.com/) workout
logger. It covers both APIs and the workflows that combine them, so an agent can
plan a session from someone's training history and write it back as a routine they
can start on their phone.

## Install

Copy `skills/hevy/` into `~/.claude/skills/` for every project, or into
`.claude/skills/` inside one repo.

```
git clone https://github.com/AboveColin/hevy-api-knowledge
cp -r hevy-api-knowledge/skills/hevy ~/.claude/skills/
```

Claude loads `SKILL.md` when a task mentions Hevy, and pulls in the references when
it needs the detail.

## What is in it

- `skills/hevy/SKILL.md` gives the orientation and the four mistakes that break most
  first attempts.
- `skills/hevy/references/api-v1.md` is the documented Pro API, checked field by
  field against Hevy's OpenAPI spec: all 14 paths, the workout, routine, template,
  history and body-measurement shapes, the three closed vocabularies, the per-endpoint
  pagination caps, and the naming traps that make a response fail to round-trip into
  a request.
- `skills/hevy/references/api-internal.md` is the app's own API, 60 endpoints
  reverse-engineered from Android client traffic on version 2.5.11. It is the only
  route to the feed, likes, comments, follows and subscription state. Endpoints
  taken from a client library rather than from captured traffic are marked
  unverified.
- `skills/hevy/references/workflows.md` is eight mechanical recipes: caching
  templates, incremental sync, estimated 1RM, weekly set volume per muscle group,
  stall detection, generating a routine from history, recovery-aware scheduling, and
  how to schedule at all when the API has no date field.
- `skills/hevy/references/coaching.md` is seven workflows that produce coaching
  output: workout review, weekly summary, exercise progression, deload check,
  four-week programme design written back as routines, and two social ones.

## Two APIs

The **v1 public API** is Hevy's own, documented at https://api.hevyapp.com/docs/,
Pro-only, one `api-key` header. Use it for anything that reads or writes training
data.

The **internal API** is undocumented and unsupported. Hevy can change it without
notice and it needs a password login. It is documented here because the public API
has no social endpoints at all, not as an alternative to paying for Pro. If you only
need workouts and routines, stay on v1.

## No personal data

Every capture in `api-internal.md` has been scrubbed: usernames, real names, account
ids, emails, tokens, profile image URLs, birthdays and body measurements are all
replaced with placeholders. `scripts/scrub-check.sh` greps for the patterns that
would indicate a leak, and `.githooks/pre-commit` runs it before every commit.

```
git config core.hooksPath .githooks
```

If you find something that slipped through, open an issue and I will strip it.

## Not affiliated with Hevy

This is an unofficial community reference. Hevy's published API is version 0.0.1 and
their own docs warn that the structure may change or the project may be dropped.
Nothing here is a promise that any of it still works.

## Licence

MIT.

---
name: hevy
description: Read and write Hevy workout data. Use when building against the Hevy API, planning or generating a routine from training history, reviewing a workout or a training week, checking for a plateau or a needed deload, computing progression or e1RM from logged sets, syncing workouts into another system, or debugging a Hevy request that returns the wrong shape.
---

# Hevy

Hevy is a workout logger. Two APIs reach the same data.

**The v1 public API** is documented by Hevy at https://api.hevyapp.com/docs/, gated
to Hevy Pro, and authenticated with a single `api-key` header. It covers workouts,
routines, routine folders, exercise templates, exercise history and body
measurements. Use it for anything that reads or writes training data. Full
reference: `references/api-v1.md`.

**The internal app API** is what the phone app uses. It is undocumented, needs a
username and password login, and carries the social side that v1 omits: the feed,
likes, comments, follows, notifications, subscription state and feature flags. It
is reverse-engineered from app traffic, so it changes without notice and Hevy
makes no promises about it. Reference: `references/api-internal.md`.

Start with v1. Reach for the internal API only when v1 has no equivalent.

## The four facts that break first attempts

`pageSize` maxes at **10** everywhere except `/v1/exercise_templates`, which allows
**100**. Going over returns 400 `Invalid page size` rather than clamping. Pulling a
year of workouts is a long crawl. Caching every exercise template is a handful of
calls.

**Routine sets and workout sets are different objects.** A routine set takes
`rep_range: {start, end}` and its exercise takes `rest_seconds`. A workout set takes
`rpe` from the fixed ladder 6, 7, 7.5, 8, 8.5, 9, 9.5, 10. Sending `rpe` to a routine
or `rep_range` to a workout is the most common first error.

**Incremental sync goes through `/v1/workouts/events?since=`**, which returns
`{"type": "updated", "workout": {...}}` and `{"type": "deleted", "id", "deleted_at"}`.
Diffing full pages of `/v1/workouts` misses deletes entirely.

**`GET /v1/routines/{id}` wraps its result** in `{"routine": {...}}` where the list
endpoint does not. Two more naming traps in the same family: a workout response calls
the superset field `supersets_id` while the request calls it `superset_id`, and
`/v1/exercise_history` calls the set type `set_type` where everything else calls it
`type`. Round-tripping a response into a request loses the superset grouping and
does not error.

## Writing a routine

A routine is the mechanism for handing someone a planned session. You create it
through the API, and it appears in their Hevy app ready to start.

```json
POST /v1/routines
{"routine": {
  "title": "Upper A",
  "folder_id": null,
  "notes": "",
  "exercises": [{
    "exercise_template_id": "79D0BB3A",
    "superset_id": null,
    "rest_seconds": 150,
    "notes": null,
    "sets": [
      {"type": "warmup", "weight_kg": 40, "reps": 8},
      {"type": "normal", "weight_kg": 80, "reps": 5,
       "rep_range": {"start": 5, "end": 8}}
    ]
  }]
}}
```

`type` is one of `warmup`, `normal`, `failure`, `dropset`. Omitted set fields default
to null. `exercise_template_id` must come from `/v1/exercise_templates`, so cache that
list before you build anything. Custom templates the user created appear in the same
list with `is_custom: true`.

`POST /v1/routines` returns 201, or 403 when the account cannot hold another
routine. `folder_id` is a number, and null files it under the default My Routines
folder.

`PUT /v1/routines/{id}` replaces the routine wholesale. There is no per-exercise
patch, so read, modify, and send the whole thing back. Its body takes only `title`,
`notes` and `exercises`, with **no `folder_id`**, so the API can place a routine in
a folder at creation and can never move it afterwards.

## Planning a session from history

`references/workflows.md` has the full recipes. The short version:

1. Cache `/v1/exercise_templates` once. It maps a template id to a title, a primary
   muscle group, secondary muscle groups and equipment. Every planning decision needs
   that mapping.
2. Read `/v1/exercise_history/{templateId}` for the exercises you are considering.
   It returns one entry per set, not per session, with no date field. Group on
   `workout_id` or on the date part of `workout_start_time`.
3. Estimate a one-rep max per session. Epley is `weight * (1 + reps / 30)`. Take the
   best set of the session, not the average.
4. Decide the next prescription from the trend, then write it as a routine.

Set weights from the athlete's own numbers. A routine full of round numbers that
ignore their history is worse than no routine.

## Coaching output

`references/coaching.md` has seven workflows that produce something for a person to
read rather than a data structure: reviewing one workout, summarising a week,
tracking one lift's progression, deciding whether a deload is due, designing a
four-week programme and writing it back as routines, and two social ones that need
the internal API.

Each names its calls and its sections. Two of them also record the mistake the
obvious implementation makes, because both are easy to ship and hard to notice.

## Scheduling

A routine has no date. Only a workout carries time, and a workout means a session
that happened, so an agent that plans training holds the calendar itself. Keep fixed
slot routines and PUT new prescriptions into them, store the schedule in your own
store, and join plan to reality through `routine_id`, which every logged workout
carries. `references/workflows.md` section 8 has the mechanisms and the one thing
not to do.

## No deletes

The API has no DELETE on any path. Nothing it creates can be removed through it, so
a script that writes a routine per day fills the user's folder until they clear it
by hand. Overwrite one routine with PUT instead of creating a new one each time.

## Rate limits

Hevy publishes none. Their own docs call the API version 0.0.1 and warn that the
structure may change or the project may be abandoned. Treat 429 and 5xx as expected,
back off, and do not build anything that hammers the endpoint in a loop.

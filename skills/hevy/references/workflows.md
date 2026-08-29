# Workflows

Recipes that combine several endpoints. Each one names the calls, the maths and the
failure it is guarding against.

## 1. Cache the exercise templates

Every other workflow needs a template id, a muscle group and an equipment type.
Nothing else gives you that mapping.

```
GET /v1/exercise_templates?page=N&pageSize=100   until page >= page_count
```

Store `id`, `title`, `type`, `primary_muscle_group`, `secondary_muscle_groups` and
`is_custom`. Those six are what the spec documents. Some clients also read an
`equipment` field that the spec does not list, so treat it as optional and never key
anything on it. Refresh on a schedule rather than per request, because the built-in
list moves rarely and a user's custom templates change only when they add one.

Match on `id`, never on `title`. Two templates can share a title across equipment
variants, and a user renaming a custom exercise breaks a title join silently.

## 2. Pull history into your own store

First run: crawl `/v1/workouts?pageSize=10` back as far as you want, then record the
current timestamp.

Every run after: `GET /v1/workouts/events?since=<last run>` and apply updates and
deletes. Record the new timestamp only after the whole run succeeds, so a crash
replays rather than skips.

Two things to decide before you write a line of it.

**Idempotency key.** A workout has one id but many exercises, and most stores want a
row per exercise or per set. `"{workout_id}_{exercise_index}"` is stable as long as
the user does not reorder exercises in an edited workout. If they do, indices shift
and you get duplicates. Keying on `workout_id` plus `exercise_template_id` survives
reordering but breaks when the same exercise appears twice in one session.

**What a re-sync does to edits.** Deleting the date range and rebuilding makes
re-syncs clean and destroys any local annotation on those rows. Upserting preserves
annotations and lets stale data survive when a workout is edited in the app. Pick one
deliberately. Doing half of each is how a store ends up with sets that no longer
match their workout.

## 3. Progression and estimated 1RM

From `/v1/exercise_history/{templateId}`, group sets into sessions. The response is
one entry per set with no date field, so group on `workout_id`, or on the date part
of `workout_start_time` if you want calendar days. The set type is `set_type` here,
not `type`.

- Estimated 1RM, Epley: `weight_kg * (1 + reps / 30)`. Use the best single set of the
  session. Averaging across sets buries the top set under the back-offs.
- Session volume: `sum(weight_kg * reps)` over working sets.
- Top set: the highest `weight_kg` at the session's highest reps for that weight.

Exclude warmup sets from volume and from the 1RM estimate. They are marked
`set_type: "warmup"` on this endpoint and `type: "warmup"` everywhere else, and
including them inflates both numbers.

Epley drifts high above roughly 10 reps. If the athlete trains in high rep ranges,
say so alongside the number rather than presenting it as a measurement.

## 4. Weekly set volume per muscle group

Count hard sets, not exercises, and not tonnage.

For each set in the window, resolve its exercise to a template, then credit the
`primary_muscle_group` a full set and each entry of `secondary_muscle_groups` a
fraction, commonly a half. The fraction is a modelling choice, so make it a named
constant and say what you chose.

Exclude warmups. Count `failure` and `dropset` sets as working sets.

This is the number most training plans are actually built on, and Hevy gives you
everything needed to compute it in two calls plus the template cache.

## 5. Detect a stalled lift

Over the last N sessions of one exercise, compare best estimated 1RM per session.

A lift has stalled when the best estimate has not improved over the last three
sessions and each of those sessions had at least as many working sets as the
session before. The second condition matters. A lift that "stalled" while the
athlete cut volume did not stall, it got less work.

Report the plateau with the numbers behind it: the three session dates, their top
sets, and their estimates. A bare "you have plateaued on bench" is not actionable
and is often wrong.

## 6. Build a session and write it as a routine

The full path from history to something the athlete can press start on.

1. Pick the muscle groups. Either from a schedule, or from recent weekly set volume
   per group against a target range, taking the groups furthest below target.
2. Pick exercises for those groups from the template cache, preferring ones the
   athlete already has history on. An exercise with no history means you have no
   basis for a weight.
3. Set the load per exercise from `/v1/exercise_history`. Take the last session's top
   set as the anchor. Repeat it, or add a small increment when the last session hit
   the top of its rep range at an RPE below 9.
4. Build the routine body. Warmup sets get `type: "warmup"`, working sets get
   `type: "normal"` plus a `rep_range`. Set `rest_seconds` per exercise, longer for
   compounds.
5. `POST /v1/routines`, or `PUT /v1/routines/{id}` to overwrite last week's copy.
   Prefer the PUT. The API has no DELETE, so every POST is permanent and a weekly
   generator buries the athlete in near-identical routines they have to clear by
   hand. The PUT body has no `folder_id`, so pick the folder at creation.

Two rules worth holding to. Never prescribe a weight for an exercise with no history,
leave it null and let the athlete fill it in. And write the reasoning into the
routine `notes` field, because a plan the athlete cannot interrogate is a plan they
will ignore.

## 7. Recovery-aware scheduling

If you want the plan to react to fatigue rather than a fixed weekly split, a
fitness-fatigue model over set volume is enough. Both fatigue and fitness decay
exponentially from each session, fatigue with a short half-life and fitness with a
long one, and readiness is fitness minus fatigue. This is the Banister model applied
per muscle group instead of per athlete.

The half-lives are the whole model and they are not universal. Pick them, write down
why, and check the output against how the athlete actually feels before trusting it
to schedule anything. A model with invented constants that nobody validated is worse
than a fixed split, because it looks principled.

Hevy gives you the input for free: dated sets, resolved to muscle groups through the
template cache.

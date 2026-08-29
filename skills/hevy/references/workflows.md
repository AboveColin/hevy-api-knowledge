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

## 8. Scheduling, when the API has no dates

A routine has no date field, only a workout does, and a workout means a session that
happened. So an agent that plans training has to hold the calendar itself and use
Hevy for content. Four mechanisms, in the order worth reaching for.

### Fixed slot routines, overwritten in place

Create the routines once, one per slot in the athlete's week, and from then on `PUT`
new prescriptions into the same ids. `Upper A`, `Lower A`, `Upper B` stay put while
their contents change weekly.

This is the right default for anything recurring. Routine ids stay stable, so your
own store can reference them. The athlete's folder never grows. And it sidesteps the
missing DELETE, which is what makes the create-a-new-one-each-week approach turn
into a folder the athlete has to clear by hand.

Two constraints when you set this up. `PUT` has no `folder_id`, so the folder is
fixed at creation. And `POST` does not accept `index`, so the order routines appear
in is the server's choice, not yours.

### Keep the schedule in your own store

One row per planned session: date, `routine_id`, and whatever reasoning produced it.
Hevy holds the exercises and the loads. You hold when.

This costs a table and buys everything the API will not do: rescheduling, a plan
further out than the routines you have slots for, and a record of what you intended
versus what you wrote.

### Close the loop with `routine_id` on the workout

A logged workout carries `routine_id`, the routine it was started from. That is the
join between what you planned and what the athlete did.

After a planned date passes, look for a workout whose `routine_id` matches the slot
and whose `start_time` falls on or near that date. Found means the session ran, and
its sets tell you at what loads. Nothing found means it was skipped, which is the
input a deload check or a next-week plan actually needs.

`/v1/workouts/events?since=` carries the full workout on every `updated` event, so
`routine_id` arrives there too. Adherence can run off the same incremental sync as
everything else rather than needing its own crawl.

### Date in the title, as a label only

The app itself does this. A routine created through the phone on 15 February went up
titled `15-feb`.

If you write dates into titles, use `YYYY-MM-DD` at the front so the strings sort in
calendar order. Treat the title as a label for the human, never as your source of
truth: an athlete renaming a routine in the app silently breaks any logic that
parses it. The same goes for stashing a marker in `notes`, which is fine for
explaining the plan to the athlete and unfit for anything you parse back.

### Do not fake a calendar entry with a future workout

`POST /v1/workouts` accepts `start_time`, so a future-dated workout looks like an
easy scheduled session. It is not. Hevy records it as a completed session, so it
lands in volume totals, PR detection, streaks and every analytic downstream. There
is no DELETE, so you cannot take it back, and the athlete has to clean it up
themselves. A plan lives in a routine or in your own store, never in the training
log.

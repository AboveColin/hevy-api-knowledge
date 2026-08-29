# Hevy v1 public API

Base URL `https://api.hevyapp.com`. Every request carries `api-key: <your key>`,
a UUID, available to Hevy Pro accounts at https://hevy.com/settings?developer.

Everything below is checked against Hevy's own OpenAPI spec at
https://api.hevyapp.com/docs/. Where this file states something the spec does not
cover, it says so. The spec calls itself version 0.0.1 and warns that the structure
may change or the project may be dropped.

## Endpoints

| Path | Methods | Success | Notes |
|---|---|---|---|
| `/v1/workouts` | GET, POST | 200 / 201 | |
| `/v1/workouts/count` | GET | 200 | `{"workout_count": n}` |
| `/v1/workouts/events` | GET | 200 | `since` param, updates and deletes |
| `/v1/workouts/{workoutId}` | GET, PUT | 200 | |
| `/v1/routines` | GET, POST | 200 / 201 | POST can return 403 |
| `/v1/routines/{routineId}` | GET, PUT | 200 | GET wraps in `{"routine": ...}` |
| `/v1/routine_folders` | GET, POST | 200 / 201 | |
| `/v1/routine_folders/{folderId}` | GET | 200 | |
| `/v1/exercise_templates` | GET, POST | 200 / 200 | POST can return 403 |
| `/v1/exercise_templates/{exerciseTemplateId}` | GET | 200 | |
| `/v1/exercise_history/{exerciseTemplateId}` | GET | 200 | `start_date`, `end_date` |
| `/v1/body_measurements` | GET, POST | 200 | |
| `/v1/body_measurements/{date}` | GET, PUT | 200 | date is `YYYY-MM-DD` |
| `/v1/user/info` | GET | 200 | `{"data": {"id", "name", "url"}}` |

There is no DELETE anywhere in the API. Nothing created through it can be removed
through it.

### Pagination

Every paginated response is `{"page": n, "page_count": n, "<collection>": [...]}`.
Loop until `page >= page_count`.

| Endpoint | pageSize default | max |
|---|---|---|
| `/v1/workouts` | 5 | 10 |
| `/v1/workouts/events` | 5 | 10 |
| `/v1/routines` | 5 | 10 |
| `/v1/routine_folders` | 5 | 10 |
| `/v1/body_measurements` | 10 | 10 |
| `/v1/exercise_templates` | 5 | **100** |

Exceeding the max returns 400 `Invalid page size`, it does not clamp. A year of
workouts is a long crawl at 10 per request. The whole template catalogue is a
handful of calls at 100.

## Exercise templates

```
GET /v1/exercise_templates?page=1&pageSize=100
```

```json
{"page": 1, "page_count": 12, "exercise_templates": [{
  "id": "79D0BB3A",
  "title": "Bench Press (Barbell)",
  "type": "weight_reps",
  "primary_muscle_group": "chest",
  "secondary_muscle_groups": ["triceps", "shoulders"],
  "is_custom": false
}]}
```

The spec lists exactly those six fields. Some clients also read an `equipment`
field off this response. It is not in the spec and I have not confirmed on a live
call whether the API returns it, so do not depend on it. Equipment appears in the
spec only as `equipment_category` on the create request.

Built-in templates carry short uppercase hex ids. Custom templates carry UUIDs and
`is_custom: true`. Both work anywhere an `exercise_template_id` is accepted.

### Creating a custom template

```json
POST /v1/exercise_templates
{"exercise": {
  "title": "Bench Press",
  "exercise_type": "weight_reps",
  "equipment_category": "barbell",
  "muscle_group": "chest",
  "other_muscles": ["biceps", "triceps"]
}}
```

Returns **200** with `{"id": 123}`, an integer, while every other template id in the
API is a string. Returns 403 `exceeds-custom-exercise-limit` when the account is at
its custom exercise cap.

- `exercise_type`: `weight_reps`, `reps_only`, `bodyweight_reps`,
  `bodyweight_assisted_reps`, `duration`, `weight_duration`, `distance_duration`,
  `short_distance_weight`
- `equipment_category`: `none`, `barbell`, `dumbbell`, `kettlebell`, `machine`,
  `plate`, `resistance_band`, `suspension`, `other`
- `muscle_group` and each entry of `other_muscles`: `abdominals`, `shoulders`,
  `biceps`, `triceps`, `forearms`, `quadriceps`, `hamstrings`, `calves`, `glutes`,
  `abductors`, `adductors`, `lats`, `upper_back`, `traps`, `lower_back`, `chest`,
  `cardio`, `neck`, `full_body`, `other`

Those three vocabularies are closed. Anything outside them is rejected, and the
muscle group list is the only grouping the API offers, so a planner has to work in
these terms.

## Workouts

### Reading

```json
{"id": "...", "title": "Morning Workout", "routine_id": "...",
 "description": "...", "start_time": "...", "end_time": "...",
 "updated_at": "...", "created_at": "...", "exercises": [...]}
```

Each exercise in a **response** is `{index, title, notes, exercise_template_id,
supersets_id, sets}` and each set is `{index, type, weight_kg, reps,
distance_meters, duration_seconds, rpe, custom_metric}`.

Note `supersets_id`, plural, in the response. The request field is `superset_id`,
singular. Round-tripping a response straight back into a POST drops the superset
grouping without erroring.

### Writing

```json
POST /v1/workouts
{"workout": {
  "title": "Friday Leg Day",
  "description": null,
  "start_time": "2024-08-14T12:00:00Z",
  "end_time": "2024-08-14T12:30:00Z",
  "is_private": false,
  "exercises": [{
    "exercise_template_id": "79D0BB3A",
    "superset_id": null,
    "notes": null,
    "sets": [{
      "type": "normal",
      "weight_kg": 80,
      "reps": 5,
      "distance_meters": null,
      "duration_seconds": null,
      "custom_metric": null,
      "rpe": 8
    }]
  }]
}}
```

Returns **201**. `type` is `warmup`, `normal`, `failure` or `dropset`. `rpe` accepts
only 6, 7, 7.5, 8, 8.5, 9, 9.5, 10, or null. Every set field except `type` is
nullable. `superset_id` is an integer shared by the exercises in one superset.

`PUT /v1/workouts/{id}` takes the same body and returns 200. It replaces the
workout, so read, modify, send it all back.

A workout carries no per-exercise duration, only `start_time` and `end_time` for the
session. Any per-exercise time is something you invent.

## Incremental sync

```
GET /v1/workouts/events?since=2024-01-01T00:00:00Z&page=1&pageSize=10
```

`since` defaults to `1970-01-01T00:00:00Z`. Each event is one of two shapes,
distinguished by `type`:

```json
{"type": "updated", "workout": { ...full workout... }}
{"type": "deleted", "id": "...", "deleted_at": "2024-01-15T18:30:00Z"}
```

Store the timestamp of your last successful run and pass it as `since`, writing the
new one only after the whole run succeeds so a crash replays rather than skips.

Paging `/v1/workouts` instead never reports a deletion, so deleted sessions live in
your copy forever.

## Routines

```json
POST /v1/routines
{"routine": {
  "title": "April Leg Day",
  "folder_id": null,
  "notes": "Focus on form over weight.",
  "exercises": [{
    "exercise_template_id": "79D0BB3A",
    "superset_id": null,
    "rest_seconds": 150,
    "notes": null,
    "sets": [{
      "type": "normal",
      "weight_kg": 80,
      "reps": 5,
      "distance_meters": null,
      "duration_seconds": null,
      "custom_metric": null,
      "rep_range": {"start": 5, "end": 8}
    }]
  }]
}}
```

Returns **201**. `folder_id` is a number, and null files the routine in the default
My Routines folder. A 403 comes back when the account cannot hold another routine.

Differences from a workout **on the request**, and the source of most 400s:

| | Routine set | Workout set |
|---|---|---|
| `rep_range` | yes | no |
| `rpe` | no | yes |
| `rest_seconds` | on the exercise | not present |
| timing | none | `start_time`, `end_time` |

A routine read back carries both `rep_range` and `rpe`, so the response is wider than
what the create and update bodies accept. Sending a routine response back unchanged
fails on `rpe`.

### No scheduling

A routine has no date. The create body takes `title`, `folder_id`, `notes` and
`exercises`, the update body drops `folder_id`, and the response adds only `id`,
`index`, `created_at` and `updated_at`. Nothing in either API attaches a routine to a
day, so a routine is a template and never a calendar entry. Only a workout carries
time, through `start_time` and `end_time`, and that records a session that happened.

The internal API has a `program_id` on its routine create, which points at Hevy's
coaching programs. It is null in every observed request and no program endpoint
appears in the public spec or in any capture, so there is no API route to
scheduling. Convention is to put the date in the routine title, which is what the
app itself does.

For what to build instead, see `workflows.md` section 8. The short version: keep
fixed slot routines and PUT into them, hold the calendar in your own store, and join
plan to reality through `routine_id` on the logged workout.

### Updating

`PUT /v1/routines/{id}` replaces the whole routine and returns 200. Its body accepts
only `title`, `notes` and `exercises`.

**There is no `folder_id` on the update body.** A routine cannot be moved between
folders through the API, only placed in one at creation.

`GET /v1/routines/{id}` wraps its result in `{"routine": {...}}`. The list endpoint
does not wrap.

## Routine folders

```json
POST /v1/routine_folders
{"routine_folder": {"title": "Push Pull"}}
```

Returns 201 with `{"id": 42, "index": 1, "title": "...", "created_at": "...",
"updated_at": "..."}`. `index` is the folder's position in the list.

## Exercise history

```
GET /v1/exercise_history/{exerciseTemplateId}?start_date=2024-01-01T00:00:00Z&end_date=2024-06-01T00:00:00Z
```

Both dates are ISO 8601 date-time, not plain dates, and both are optional.

```json
{"exercise_history": [{
  "workout_id": "...",
  "workout_title": "Morning Workout",
  "workout_start_time": "2024-01-15T18:30:00Z",
  "workout_end_time": "2024-01-15T19:30:00Z",
  "exercise_template_id": "79D0BB3A",
  "weight_kg": 80,
  "reps": 5,
  "distance_meters": null,
  "duration_seconds": null,
  "rpe": 8,
  "custom_metric": null,
  "set_type": "normal"
}]}
```

**One entry per set, not per session, and there is no date field.** Group on
`workout_id`, or on the date part of `workout_start_time`. The set type lives in
`set_type` here, where everywhere else in the API it is `type`.

This is the cheapest route to a progression series. The alternative is crawling
every workout page at 10 per request and filtering client side.

## Body measurements

`GET /v1/body_measurements` pages at 10, which is also its default.

```json
POST /v1/body_measurements
{"date": "2024-01-15", "weight_kg": 72, "fat_percent": 15}
```

`date` is the only required field, format `YYYY-MM-DD`. Every measurement is
optional and nullable: `weight_kg`, `lean_mass_kg`, `fat_percent`, `neck_cm`,
`shoulder_cm`, `chest_cm`, `left_bicep_cm`, `right_bicep_cm`, `left_forearm_cm`,
`right_forearm_cm`, `abdomen`, `waist`, `hips`, `left_thigh`, `right_thigh`,
`left_calf`, `right_calf`.

The last seven carry no unit suffix in their names while the first ten do. The
naming is inconsistent in the API itself, not here.

`PUT /v1/body_measurements/{date}`, in Hevy's own words: "All fields are
overwritten; omitted fields are set to null." So a PUT that sends only `weight_kg`
wipes every other measurement for that date. Read the record first and send it back
whole.

## Errors

400 on a bad body or an out-of-range page size, shaped `{"error": "message"}`.
403 on the create limits for routines and custom exercises. 404 on a missing id.
500 is documented on `/v1/workouts/events`.

Rate limits are not documented anywhere, and no rate limit headers are specified.
Treat 429 and 5xx as expected and back off.

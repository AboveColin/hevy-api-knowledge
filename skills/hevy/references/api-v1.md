# Hevy v1 public API

Base URL `https://api.hevyapp.com`. Every request carries `api-key: <your key>`.
The key is a UUID, available to Hevy Pro accounts at
https://hevy.com/settings?developer. Hevy's own docs live at
https://api.hevyapp.com/docs/ and describe the API as version 0.0.1, with a
warning that they may change the structure or drop it.

## Endpoints

| Path | Methods | Notes |
|---|---|---|
| `/v1/workouts` | GET, POST | `page`, `pageSize` (max 10) |
| `/v1/workouts/count` | GET | `{"workout_count": n}` |
| `/v1/workouts/events` | GET | `since` (ISO 8601), returns updates and deletes |
| `/v1/workouts/{workoutId}` | GET, PUT | |
| `/v1/routines` | GET, POST | `page`, `pageSize` (max 10) |
| `/v1/routines/{routineId}` | GET, PUT | GET wraps in `{"routine": ...}` |
| `/v1/routine_folders` | GET, POST | `page`, `pageSize` (max 10) |
| `/v1/routine_folders/{folderId}` | GET | |
| `/v1/exercise_templates` | GET, POST | `page`, `pageSize` (max 100) |
| `/v1/exercise_templates/{exerciseTemplateId}` | GET | |
| `/v1/exercise_history/{exerciseTemplateId}` | GET | `start_date`, `end_date` |
| `/v1/body_measurements` | GET, POST | `pageSize` max 10 |
| `/v1/body_measurements/{date}` | GET, PUT | date is `YYYY-MM-DD` |
| `/v1/user/info` | GET | `{"data": {"id", "name", "url"}}` |

Paginated responses look like `{"page": 1, "page_count": 12, "<collection>": [...]}`.
Loop until `page >= page_count`.

## Exercise templates

```
GET /v1/exercise_templates?page=1&pageSize=100
```

```json
{"exercise_templates": [{
  "id": "79D0BB3A",
  "title": "Bench Press (Barbell)",
  "type": "weight_reps",
  "primary_muscle_group": "chest",
  "secondary_muscle_groups": ["triceps", "shoulders"],
  "equipment": "barbell",
  "is_custom": false
}]}
```

Built-in templates have short uppercase hex ids. Templates the user created
themselves have UUID ids and `is_custom: true`. Both work anywhere a
`exercise_template_id` is accepted.

`POST /v1/exercise_templates` creates a custom one and returns `{"id": n}`.

- `exercise_type`: `weight_reps`, `reps_only`, `bodyweight_reps`,
  `bodyweight_assisted_reps`, `duration`, `weight_duration`, `distance_duration`,
  `short_distance_weight`
- `equipment_category`: `none`, `barbell`, `dumbbell`, `kettlebell`, `machine`,
  `plate`, `resistance_band`, `suspension`, `other`
- `muscle_group` and each entry of `other_muscles`: `abdominals`, `shoulders`,
  `biceps`, `triceps`, `forearms`, `quadriceps`, `hamstrings`, `calves`, `glutes`,
  `abductors`, `adductors`, `lats`, `upper_back`, `traps`, `lower_back`, `chest`,
  `cardio`, `neck`, `full_body`, `other`

The muscle group vocabulary is fixed. Anything outside it is rejected, and it is
the only grouping the API gives you, so a planner has to work in these terms.

## Workouts

```json
POST /v1/workouts
{"workout": {
  "title": "Evening Workout",
  "description": null,
  "start_time": "2024-01-01T18:00:00Z",
  "end_time": "2024-01-01T19:05:00Z",
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

`type` is `warmup`, `normal`, `failure` or `dropset`. `rpe` accepts only 6, 7, 7.5,
8, 8.5, 9, 9.5, 10, or null. `superset_id` is an integer shared by the exercises in
one superset, null otherwise.

`PUT /v1/workouts/{id}` takes the same body and replaces the workout.

A workout carries no per-exercise duration. Only `start_time` and `end_time` for the
whole session, so any per-exercise time is an estimate you invent.

## Incremental sync

```
GET /v1/workouts/events?since=2024-01-01T00:00:00Z&page=1&pageSize=10
```

Returns `{"page", "page_count", "events": [...]}` where each event is an update or a
delete. Store the timestamp of your last successful run and pass it as `since`.
Paging through `/v1/workouts` instead will never tell you a workout was deleted, so
deleted sessions linger in your copy forever.

## Routines

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

Differences from a workout, and the source of most 400s:

| | Routine set | Workout set |
|---|---|---|
| `rep_range` | yes | no |
| `rpe` | no | yes |
| `rest_seconds` | on the exercise | not present |
| timing | none | `start_time`, `end_time` required |

`folder_id` is a number or null. Create folders with
`POST /v1/routine_folders {"routine_folder": {"title": "..."}}`.

`PUT /v1/routines/{id}` replaces the whole routine. Read it, change what you need,
send it all back.

## Exercise history

```
GET /v1/exercise_history/{exerciseTemplateId}?start_date=2024-01-01&end_date=2024-06-01
```

Returns `{"exercise_history": [...]}` with dated set entries. This is the cheapest
path to a progression series, because the alternative is crawling every workout page
at 10 per request and filtering client side.

## Body measurements

`GET /v1/body_measurements` pages at 10. `POST` takes a record with a required `date`
plus optional `weight_kg`, `lean_mass_kg`, `fat_percent` and circumference fields.
`PUT /v1/body_measurements/{date}` sets omitted fields to null rather than leaving
them alone, so read before you write.

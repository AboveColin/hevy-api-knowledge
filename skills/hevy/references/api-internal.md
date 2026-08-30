# Hevy API Documentation

**Base URL:** `https://api.hevyapp.com`
**Protocol:** HTTPS
**Server:** Heroku (Express.js)
**Content-Type:** `application/json; charset=utf-8`
**Observed App Version:** 3.1.11 (Build 3265149, Android), diffed against 2.5.11.
The 2.x endpoint and payload shapes below still hold in 3.1.11. The 3.x additions
(gyms and workout location, Hevy Trainer v3, a linked-session auth call) are listed
in the "Added in 3.x" section near the end. All 3.x items come from the Hermes
string table, so paths are observed and methods are unverified.

> This documentation is reverse-engineered from observed API traffic of the Hevy workout tracking app (Android client). It covers the internal/private API, not the official public API.

**Provenance.** Every endpoint below came from captured traffic except seven, which
came from a client library and have no capture behind them: `GET /users/search`,
`GET /users/{username}`, `GET /followers/{username}`, `GET /following/{username}`,
`GET /workout_likes/{id}`, `GET /workout_comments/{id}` and `GET /routine/{id}`.
Treat those seven as unverified. The shapes are probably right and nobody has
watched them on the wire.

**The app also talks to two third parties.** Subscription entitlements come from
RevenueCat, not from Hevy, so `GET /user_subscription` is Hevy's own mirror of that
state rather than the source. Attribution events go to Adjust. Neither is part of
the Hevy API and neither is documented here.

---

## Table of Contents

1. [Authentication](#1-authentication)
2. [Common Headers](#2-common-headers)
3. [Worked example: log in and write a routine](#2b-worked-example-log-in-and-write-a-routine)
3. [User Account & Profile](#3-user-account--profile)
4. [User Preferences](#4-user-preferences)
5. [Workouts](#5-workouts)
6. [Workout Feed](#6-workout-feed)
7. [Workout Interactions](#7-workout-interactions)
8. [Routines](#8-routines)
9. [Exercises](#9-exercises)
10. [Social & Friends](#10-social--friends)
11. [Notifications](#11-notifications)
12. [Push Notifications](#12-push-notifications)
13. [Body Measurements](#13-body-measurements)
14. [Plate Calculator](#14-plate-calculator)
15. [Subscription & Promotions](#15-subscription--promotions)
16. [App Configuration](#16-app-configuration)
17. [Analytics & Metadata](#17-analytics--metadata)
18. [Data Models](#18-data-models)

---

## 1. Authentication

The API uses a dual-token authentication system with Bearer tokens and auth-tokens.

### POST `/login`

Authenticates a user with email/username and password. Returns session tokens.

**Authentication:** API key only (no bearer token)
**Status:** `200 OK`

**Request Body:**
```json
{
  "emailOrUsername": "user@example.com",
  "password": "your_password",
  "useAuth2_0": true,
  "recaptchaToken": "optional_recaptcha_token"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `emailOrUsername` | string | Yes | Email address or username |
| `password` | string | Yes | Account password |
| `useAuth2_0` | boolean | Yes | Use auth 2.0 flow (always `true`) |
| `recaptchaToken` | string | No | reCAPTCHA token (may be required when `enable_login_recaptcha` flag is active) |

**Response Body:**
```json
{
  "auth_token": "a5c8524a-fe13-467f-a63a-62ebe0a689fa",
  "user_id": "ec55f0ba-b60d-4da7-a0d7-fa75572e2d2d",
  "access_token": "<redacted>",
  "refresh_token": "<redacted>",
  "expires_at": "2024-01-15T18:30:00.000Z"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `auth_token` | string (UUID) | Session auth token for `auth-token` header |
| `user_id` | string (UUID) | Authenticated user's ID |
| `access_token` | string | Bearer access token |
| `refresh_token` | string | Refresh token for obtaining new access tokens |
| `expires_at` | string (ISO 8601) | Access token expiration (~15 minutes) |

### POST `/auth/refresh_token`

Refreshes an expired access token using a refresh token.

**Authentication:** Bearer token (expiring)
**Status:** `200 OK`

**Request Body:**
```json
{
  "refresh_token": "<redacted>"
}
```

**Response Body:**
```json
{
  "access_token": "<redacted>",
  "refresh_token": "<redacted>",
  "expires_at": "2024-01-15T18:30:00.000Z"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `access_token` | string | New Bearer access token |
| `refresh_token` | string | New refresh token (rotated) |
| `expires_at` | string (ISO 8601) | Expiration time of the access token (~15 minutes) |

### DELETE `/auth/session`

Logs out the current user and invalidates the session.

**Authentication:** Required
**Status:** `204 No Content`
**Response Body:** Empty

---

## 2. Common Headers

### Required Request Headers

| Header | Value | Description |
|--------|-------|-------------|
| `x-api-key` | `<app api key>` | Static string compiled into the client, same for every user. Not printed here; read it out of the app bundle. |
| `hevy-app-version` | `3.1.11` | App version string |
| `hevy-app-build` | `3265149` | App build number |
| `hevy-platform` | `android 34` | Platform identifier (format: `{os} {api_level}`) |
| `authorization` | `Bearer {access_token}` | Bearer authentication token |
| `auth-token` | `{uuid}` | Session auth token (UUID format) |
| `accept` | `application/json, text/plain, */*` | Accepted content types |

### Caching Headers

The API supports ETags for conditional requests:
- Request: `If-None-Match: W/"..."`
- Response: `304 Not Modified` when data hasn't changed
- Request: `If-Modified-Since: {date}` for time-based caching

### CORS Headers (Response)

```
Access-Control-Allow-Headers: Origin, X-Requested-With, Content-Type, Accept, x-api-key, auth-token, session-token, temp-auth-token, Authorization, Hevy-App-Version, Hevy-App-Build, Hevy-Platform
Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS
```

---

## 1c. Added in 3.x (observed in the 3.1.11 bundle)

These strings are new in 3.1.11 versus 2.5.11. They come from the Hermes string
table, which holds every path and field name but not the HTTP method or the request
shape, so treat methods and nesting as unverified until watched on the wire.

### Gyms and workout location

The app gained gym tagging: a workout can be linked to a gym, and a gym has a place
with coordinates. None of this is in the v1 public API, checked against the live
OpenAPI spec, so it is internal-only as of this build.

- Endpoints (relative paths, as the internal API names them): `gyms/search`,
  `gyms/popular`, `gyms/visited`
- New fields: `gym_id`, `place_id`, `latitude`, `longitude`, `coordinate`,
  `coordinates`, `home_gym`, `user_gym`, `garage_gym`, `gyms_profile`
- Gympass integration: `link_with_gympass`

### Hevy Trainer v3

- `hevy_trainer/v3/program`, `hevy_trainer/v3/migrate`
- New field `trainer_workout_template_id`

### Auth

- `auth/create_linked_session`, a new call alongside `/login` and
  `/login_with_saved_account`.

### Billing is RevenueCat, not Hevy

3.1.11 bundles RevenueCat's billing SDK. The strings `checkout.*`, `/rcbilling/v1`,
`/v1/subscribers`, `/v1/receipts`, `/v1/events` and `revenuecat_user_id` belong to
`api.revenuecat.com`, not to Hevy. Subscription state originates at RevenueCat and
Hevy mirrors it through `/user_subscription`, consistent with 2.x.

---

## 2b. Worked example: log in and write a routine

Every request carries the app headers. An authenticated one adds two credentials,
the bearer and the session `auth-token`. Replace `<app api key>` with the static
client key, which is described in the header table above.

### Log in

```bash
curl -s https://api.hevyapp.com/login \
  -H 'x-api-key: <app api key>' \
  -H 'hevy-app-version: 3.1.11' \
  -H 'hevy-app-build: 3265149' \
  -H 'hevy-platform: android 34' \
  -H 'accept: application/json, text/plain, */*' \
  -H 'content-type: application/json; charset=utf-8' \
  -d '{"emailOrUsername":"user@example.com","password":"...","useAuth2_0":true}'
```

Returns `auth_token`, `user_id`, `access_token`, `refresh_token` and `expires_at`.
The access token lasts about 15 minutes.

`POST /login_with_saved_account` takes `{"userId","secret"}` and returns the same
object, which is how the app re-authenticates without storing a password.

### Call an authenticated endpoint

```bash
curl -s https://api.hevyapp.com/user/account \
  -H 'x-api-key: <app api key>' \
  -H 'hevy-app-version: 3.1.11' \
  -H 'hevy-app-build: 3265149' \
  -H 'hevy-platform: android 34' \
  -H "authorization: Bearer $ACCESS_TOKEN" \
  -H "auth-token: $AUTH_TOKEN" \
  -H 'accept: application/json, text/plain, */*'
```

### Create a routine

The client generates the id and the server echoes it back.

```bash
ID=$(uuidgen | tr 'A-Z' 'a-z')
curl -s https://api.hevyapp.com/routine \
  -H 'x-api-key: <app api key>' \
  -H 'hevy-app-version: 3.1.11' -H 'hevy-app-build: 3265149' \
  -H 'hevy-platform: android 34' \
  -H "authorization: Bearer $ACCESS_TOKEN" -H "auth-token: $AUTH_TOKEN" \
  -H 'content-type: application/json; charset=utf-8' \
  -d "{\"routine\":{\"title\":\"Upper A\",\"folder_id\":null,\"index\":-1,
       \"program_id\":null,\"notes\":null,
       \"clientId\":\"$ID\",\"_unsyncedObjectId\":\"$ID\",
       \"exercises\":[{\"exercise_template_id\":\"79D0BB3A\",\"notes\":\"\",
         \"rest_seconds\":150,
         \"sets\":[{\"index\":0,\"indicator\":\"normal\",\"weight_kg\":60,\"reps\":8}]}]}}"
```

Response: `{"routineId": "<the id you sent>"}`.

### Refresh

```bash
curl -s https://api.hevyapp.com/auth/refresh_token \
  -H 'x-api-key: <app api key>' \
  -H 'hevy-app-version: 3.1.11' -H 'hevy-app-build: 3265149' \
  -H 'hevy-platform: android 34' \
  -H "authorization: Bearer $ACCESS_TOKEN" -H "auth-token: $AUTH_TOKEN" \
  -H 'content-type: application/json; charset=utf-8' \
  -d "{\"refresh_token\":\"$REFRESH_TOKEN\"}"
```

Both tokens rotate. Store the new `refresh_token` or the next refresh fails.

### Four things that bite

`hevy-platform` is `{os} {api_level}` with a space, so `android 34`, not `android34`.

The web flow is a different shape: its own web api key, `hevy-platform: web`, and
**no `auth-token` header at all**. Sending the Android key with `hevy-platform: web`
is not a valid combination.

`POST /login` can demand a `recaptchaToken` when the `enable_login_recaptcha`
feature flag is on for that account. There is no way to know in advance.

The access token expires in roughly 15 minutes, which is short enough that any
script running longer than a single call needs refresh handling rather than a
token pasted into an environment variable.

---

## 3. User Account & Profile

### GET `/user/account`

Returns the authenticated user's full account details.

**Authentication:** Required
**Status:** `200 OK`

**Response Body:**
```json
{
  "id": "ec55f0ba-b60d-4da7-a0d7-fa75572e2d2d",
  "username": "example_user",
  "email": "user@example.com",
  "full_name": "",
  "description": "",
  "profile_pic": "https://cdn.example.com/profile.jpg",
  "is_strava_connected": false,
  "is_chatgpt_oauth_authorized": false,
  "country_code": "US",
  "likes_push_enabled": true,
  "follows_push_enabled": true,
  "comments_push_enabled": true,
  "comment_mention_push_enabled": true,
  "comment_discussion_push_enabled": true,
  "private_profile": false,
  "created_at": "2024-01-15T18:30:00.000Z",
  "last_workout_at": "2024-01-15T18:30:00.000Z",
  "accepted_terms_and_conditions": true,
  "is_coached": false,
  "is_a_coach": false,
  "sex": "other",
  "birthday": "1990-01-01",
  "email_consent": false,
  "email_verified": true,
  "is_hevy_trainer_user": false
}
```

| Field | Type | Description |
|-------|------|-------------|
| `id` | string (UUID) | Unique user identifier |
| `username` | string | User's username |
| `email` | string | User's email address |
| `full_name` | string | Display name |
| `description` | string | User bio/description |
| `profile_pic` | string (URL) | Profile picture URL (CloudFront CDN) |
| `is_strava_connected` | boolean | Whether Strava integration is active |
| `is_chatgpt_oauth_authorized` | boolean | Whether ChatGPT OAuth is authorized |
| `country_code` | string | ISO country code |
| `likes_push_enabled` | boolean | Push notification setting for likes |
| `follows_push_enabled` | boolean | Push notification setting for follows |
| `comments_push_enabled` | boolean | Push notification setting for comments |
| `comment_mention_push_enabled` | boolean | Push notification for @mentions |
| `comment_discussion_push_enabled` | boolean | Push notification for discussion replies |
| `private_profile` | boolean | Whether profile is private |
| `created_at` | string (ISO 8601) | Account creation timestamp |
| `last_workout_at` | string (ISO 8601) | Timestamp of last workout |
| `accepted_terms_and_conditions` | boolean | Terms acceptance status |
| `is_coached` | boolean | Whether user is a coached client |
| `is_a_coach` | boolean | Whether user is a coach |
| `sex` | string | User's sex (`"male"`, `"female"`) |
| `birthday` | string (date) | User's birthday (`YYYY-MM-DD`) |
| `email_consent` | boolean | Email marketing consent |
| `email_verified` | boolean | Whether email is verified |
| `is_hevy_trainer_user` | boolean | Whether user has Hevy Trainer access |

### GET `/user_profile/{username}`

Returns a public profile view for any user.

**Authentication:** Required
**Status:** `200 OK`

**Path Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `username` | string | The username to look up |

**Response Body:**
```json
{
  "username": "example_user",
  "verified": false,
  "subscribed": false,
  "profile_pic": "https://...jpg",
  "workout_count": 210,
  "is_blocked": false,
  "following_status": "not-following",
  "is_followed_by_requester": false,
  "private_profile": false,
  "follower_count": 21,
  "following_count": 22,
  "routines": [
    {
      "id": "ec55f0ba-...",
      "title": "Hardlopen",
      "short_id": "H68nl6RqaPc",
      "folder_id": null
    }
  ],
  "weekly_workout_durations": [
    {
      "week_start_date": "2024-01-15T18:30:00.000Z",
      "week_end_date": "2024-01-15T18:30:00.000Z",
      "total_seconds": 15353
    }
  ],
  "mutual_followers": [
    {
      "username": "friend_one",
      "profile_pic": "https://..."
    }
  ]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `username` | string | The user's username |
| `verified` | boolean | Whether the account is verified |
| `subscribed` | boolean | Whether the user has a subscription |
| `profile_pic` | string (URL) | Profile picture URL |
| `workout_count` | number | Total number of workouts |
| `is_blocked` | boolean | Whether the requesting user has blocked this user |
| `following_status` | string | Follow status: `"not-following"`, `"following"`, `"pending"` |
| `is_followed_by_requester` | boolean | Whether the requester follows this user |
| `private_profile` | boolean | Whether the profile is private |
| `follower_count` | number | Number of followers |
| `following_count` | number | Number of users followed |
| `routines` | array | Public routines list |
| `weekly_workout_durations` | array | Last 12 weeks of workout duration data |
| `mutual_followers` | array | Users that both the requester and the profile user follow |

### GET `/user_workout_streak_count/{username}`

Returns the current workout streak count for a user.

**Authentication:** Required
**Status:** `200 OK`

**Path Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `username` | string | The username to check |

### GET `/user_media/{username}`

Returns media (photos/videos) from a user's workouts.

**Authentication:** Required
**Status:** `200 OK`

**Query Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `limit` | number | Number of media items to return |
| `lessThanIndex` | number | Pagination cursor (workout index) |

**Response Body:**
```json
[
  {
    "workout_id": "ec55f0ba-...",
    "workout_name": "Met matthijs",
    "workout_index": 192665919,
    "url": "https://cdn.example.com/profile.jpg",
    "thumbnail_url": null,
    "type": "image"
  }
]
```

---

## 4. User Preferences

### GET `/user_preferences`

Returns the authenticated user's app preferences.

**Authentication:** Required
**Status:** `200 OK`

**Response Body:**
```json
{
  "username": "example_user",
  "weight_unit": "kg",
  "distance_unit": "kilometers",
  "body_measurement_unit": "cm",
  "first_weekday": "monday",
  "default_rest_timer_seconds": 150,
  "workout_keep_awake": true,
  "superset_scrolling": false,
  "plate_calculator_enabled": true,
  "rpe_enabled": true,
  "inline_set_timer_enabled": true,
  "default_workout_visibility_public": true,
  "volume_includes_warmup_sets": true
}
```

| Field | Type | Description |
|-------|------|-------------|
| `weight_unit` | string | Weight unit: `"kg"` or `"lbs"` |
| `distance_unit` | string | Distance unit: `"kilometers"` or `"miles"` |
| `body_measurement_unit` | string | Body measurement unit: `"cm"` or `"in"` |
| `first_weekday` | string | First day of week: `"monday"` or `"sunday"` |
| `default_rest_timer_seconds` | number | Default rest timer in seconds |
| `workout_keep_awake` | boolean | Keep screen awake during workout |
| `superset_scrolling` | boolean | Enable superset scrolling UI |
| `plate_calculator_enabled` | boolean | Enable plate calculator feature |
| `rpe_enabled` | boolean | Enable RPE (Rate of Perceived Exertion) tracking |
| `inline_set_timer_enabled` | boolean | Show inline set timer |
| `default_workout_visibility_public` | boolean | Default workout visibility |
| `volume_includes_warmup_sets` | boolean | Include warmup sets in volume calculation |

### PUT `/user_preferences`

Updates one or more user preferences.

**Authentication:** Required
**Status:** `200 OK`

**Request Body** (partial update supported):
```json
{
  "body_measurement_unit": "cm"
}
```

**Response Body:** Returns the full updated preferences object (same schema as GET).

### GET `/user_key_values`

Returns user-specific key-value settings.

**Authentication:** Required
**Status:** `200 OK`

---

## 5. Workouts

### GET `/workout/{workout_id}`

Returns a single workout by ID with all exercise data.

**Authentication:** Required
**Status:** `200 OK`

**Path Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `workout_id` | string (UUID) | The workout's unique identifier |

**Response Body:** See [Workout Object](#workout-object) in Data Models.

### PUT `/v2/workout/{workout_id}`

Updates an existing workout (v2 API).

**Authentication:** Required
**Status:** `200 OK`
**Response Body:** Empty (Content-Length: 0)

**Path Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `workout_id` | string (UUID) | The workout's unique identifier |

**Request Body:**
```json
{
  "workoutUpdate": {
    "exercises": [
      {
        "title": "Chest Fly (Machine)",
        "exercise_template_id": "78683336",
        "rest_timer_seconds": 0,
        "notes": "",
        "volume_doubling_enabled": false,
        "sets": [
          {
            "index": 0,
            "type": "normal",
            "weight_kg": 70,
            "reps": 13,
            "completed_at": "2024-01-15T18:30:00.000Z"
          }
        ]
      }
    ],
    "start_and_end_time": {
      "start_time": 1771132981,
      "end_time": 1771135927
    }
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `workoutUpdate.exercises` | array | Array of exercise objects |
| `workoutUpdate.exercises[].title` | string | Exercise name |
| `workoutUpdate.exercises[].exercise_template_id` | string | Exercise template reference |
| `workoutUpdate.exercises[].rest_timer_seconds` | number | Rest timer between sets (0 = disabled) |
| `workoutUpdate.exercises[].notes` | string | Notes for this exercise |
| `workoutUpdate.exercises[].volume_doubling_enabled` | boolean | Double volume counting (e.g., single-arm exercises) |
| `workoutUpdate.exercises[].sets` | array | Array of set objects |
| `workoutUpdate.exercises[].sets[].index` | number | Set order index |
| `workoutUpdate.exercises[].sets[].type` | string | Set type: `"normal"`, `"warmup"`, `"dropset"`, `"failure"` |
| `workoutUpdate.exercises[].sets[].weight_kg` | number | Weight in kilograms |
| `workoutUpdate.exercises[].sets[].reps` | number | Number of reps |
| `workoutUpdate.exercises[].sets[].completed_at` | string (ISO 8601) | When the set was completed |
| `workoutUpdate.start_and_end_time.start_time` | number (unix) | Workout start time (unix timestamp in seconds) |
| `workoutUpdate.start_and_end_time.end_time` | number (unix) | Workout end time (unix timestamp in seconds) |

### GET `/user_workouts_paged`

Returns paginated workouts for a specific user.

**Authentication:** Required
**Status:** `200 OK`

**Query Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `username` | string | Yes | Username to fetch workouts for |
| `limit` | number | Yes | Number of workouts per page |
| `offset` | number | Yes | Pagination offset |

**Response Body:**
```json
{
  "workouts": [/* array of Workout objects */]
}
```

### POST `/workouts_sync_batch`

Syncs workouts between client and server. Used on app startup to detect changes.

**Authentication:** Required
**Status:** `200 OK`

**Request Body:**
A JSON object mapping workout UUIDs to their `updated_at` timestamps, plus a `workouts_updated_at` field:
```json
{
  "bb849d24-5500-4b50-aa0e-abdffac7ac63": "2024-01-15T18:30:00.000Z",
  "664dfb2a-e05e-4b5d-af0c-c0ad8a4ebf57": "2024-01-15T18:30:00.000Z",
  "workouts_updated_at": "2024-01-15T18:30:00.000Z"
}
```

**Response Body:**
```json
{
  "updated": [/* array of full Workout objects that have been modified */],
  "deleted": [/* array of deleted workout IDs */],
  "isMore": false,
  "updated_at": "2024-01-15T18:30:00.000Z"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `updated` | array | Workout objects that have changed since the provided timestamps |
| `deleted` | array | IDs of workouts that have been deleted |
| `isMore` | boolean | Whether there are more results to sync (pagination) |
| `updated_at` | string (ISO 8601) | Latest update timestamp |

### GET `/workouts_batch/{last_index}`

Returns a batch of workouts for incremental syncing, starting from the given index.

**Authentication:** Required
**Status:** `200 OK`

**Path Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `last_index` | number | The workout index to start from (0 for initial sync) |

---

## 6. Workout Feed

### GET `/feed_workouts_paged`

Returns the workout feed (workouts from users you follow). Used as the home feed.

**Authentication:** Required
**Status:** `200 OK`

**Query Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| (none observed) | | Initial call returns the most recent feed items |

**Pagination:** Subsequent requests use different internal indexes (observed as path parameters like `/feed_workouts_paged/{last_index}`)

**Response Body:**
```json
{
  "workouts": [/* array of Workout objects from followed users */]
}
```

### GET `/feed_workouts_paged/{last_index}`

Returns the next page of feed workouts, loading older entries.

**Path Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `last_index` | number | The workout index to paginate from |

---

## 7. Workout Interactions

### POST `/workout/like/{workout_id}`

Likes a workout. Acts as a toggle (calling again unlikes).

**Authentication:** Required
**Status:** `200 OK`
**Request Body:** Empty (Content-Length: 0)
**Response Body:** Empty

---

## 8. Routines

### POST `/routines_sync_batch`

Syncs routines between client and server. Same batch sync pattern as workouts.

**Authentication:** Required
**Status:** `200 OK`

**Request Body:**
```json
{
  "f3f5be80-bc03-4389-a5e2-03843d971baf": "2024-01-15T18:30:00.000Z",
  "033e4046-dc42-439f-a4a3-dd99f6b20565": "2024-01-15T18:30:00.000Z",
  "5cd35d50-aaae-475c-a108-0a6c2b7393c7": "2024-01-15T18:30:00.000Z",
  "routines_updated_at": "2024-01-15T18:30:00.000Z"
}
```

**Response Body:**
```json
{
  "updated": [],
  "deleted": [],
  "isMore": false,
  "updated_at": "2024-01-15T18:30:00.000Z"
}
```

### POST `/routine`

Creates a routine. The client generates the id, sends it as both `clientId` and
`_unsyncedObjectId`, and the server echoes it back as `routineId`. So the id is
known before the request goes out, which is how the app writes offline and
reconciles later.

**Authentication:** Required
**Status:** `200 OK`

**Request Body:**
```json
{"routine": {
  "title": "Upper A",
  "folder_id": null,
  "index": -1,
  "program_id": null,
  "notes": null,
  "clientId": "9f2a4c71-0000-4000-a000-000000000001",
  "_unsyncedObjectId": "9f2a4c71-0000-4000-a000-000000000001",
  "exercises": [{
    "exercise_template_id": "79D0BB3A",
    "notes": "",
    "rest_seconds": 150,
    "sets": [
      {"index": 0, "indicator": "normal", "weight_kg": 68, "reps": 12},
      {"index": 1, "indicator": "normal", "weight_kg": 52, "reps": 5}
    ]
  }]
}}
```

| Field | Type | Description |
|-------|------|-------------|
| `title` | string | Routine name |
| `folder_id` | string \| null | Routine folder to file it under |
| `index` | int | Sort position. `-1` puts it at the end |
| `program_id` | string \| null | Coaching program this belongs to |
| `clientId` | string (UUID) | Client-generated routine id, returned as `routineId` |
| `_unsyncedObjectId` | string (UUID) | Same value as `clientId` |
| `exercises[].rest_seconds` | int | Rest timer for that exercise |
| `exercises[].sets[].index` | int | Zero-based position within the exercise |
| `exercises[].sets[].indicator` | string | `normal`, `warmup`, `failure`, `dropset` |

**Response Body:**
```json
{"routineId": "9f2a4c71-0000-4000-a000-000000000001"}
```

An exercise with no target load still needs one set. The app sends
`{"index": 0, "indicator": "normal", "weight_kg": 0}` with no `reps` for
bodyweight and untargeted exercises.

**This is not the v1 shape.** The public API calls the same field `type` where
this calls it `indicator`, takes `rep_range` where this takes nothing, and needs
no `index` because array order carries it. Payloads do not transfer between the
two.

---

### POST `/body_measurements_batch`

Writes one or more body measurements in a single call. Same client-generated id
pattern as routines.

**Authentication:** Required
**Status:** `200 OK`

**Request Body:**
```json
{"measurementsBatch": [{
  "date": "2024-01-15",
  "weight_kg": 72,
  "lean_mass_kg": 65,
  "fat_percent": 15,
  "_unsyncedObjectId": "9f2a4c71-0000-4000-a000-000000000002"
}]}
```

`date` is `YYYY-MM-DD`. Every measurement field is optional, so a weigh-in can
send `weight_kg` alone.

---

### GET `/routine_folders`

Returns the user's routine folder organization.

**Authentication:** Required
**Status:** `200 OK`

---

## 9. Exercises

### GET `/custom_exercise_templates`

Returns the user's custom-created exercise templates.

**Authentication:** Required
**Status:** `200 OK`

### GET `/exercise_template_units`

Returns unit configurations for exercise templates.

**Authentication:** Required
**Status:** `200 OK`

### GET `/exercise_bar_preferences`

Returns the user's barbell preferences for exercises (used with plate calculator).

**Authentication:** Required
**Status:** `200 OK`

### GET `/user_warmup_calculator_data`

Returns warmup calculator configuration data.

**Authentication:** Required
**Status:** `200 OK`

---

## 10. Social & Friends

### GET `/friends`

Returns the authenticated user's friends list.

**Authentication:** Required
**Status:** `200 OK`

### GET `/follow_counts`

Returns follower and following counts for the authenticated user.

**Authentication:** Required
**Status:** `200 OK`

### GET `/following_statuses`

Returns the follow status for all users the authenticated user has interacted with.

**Authentication:** Required
**Status:** `200 OK`

### GET `/follow_requests`

Returns pending follow requests (for private accounts).

**Authentication:** Required
**Status:** `200 OK`

### GET `/blocked_users`

Returns the list of users blocked by the authenticated user.

**Authentication:** Required
**Status:** `200 OK`

### GET `/suggested_users`

Returns suggested users to follow, based on contacts, mutual follows, location, and popularity.

**Authentication:** Required
**Status:** `200 OK`

**Response Body:**
```json
[
  {
    "id": "ec55f0ba-...",
    "username": "friend_two",
    "profile_pic": "https://...",
    "verified": false,
    "full_name": "Example Name",
    "following_status": "not-following",
    "private_profile": false,
    "source": "contact",
    "label": "contact"
  }
]
```

| Field | Type | Description |
|-------|------|-------------|
| `id` | string (UUID) | User ID |
| `username` | string | Username |
| `profile_pic` | string (URL) | Profile picture URL |
| `verified` | boolean | Verified account flag |
| `full_name` | string | Display name |
| `following_status` | string | Current follow status |
| `private_profile` | boolean | Whether the user has a private profile |
| `source` | string | How the user was discovered: `"contact"`, `"local"`, `"mutual_follows"`, `"popular"` |
| `label` | string | UI label: `"contact"`, `"featured"`, `"mutual_friends"` |

---

## 11. Notifications

### GET `/notifications`

Returns the authenticated user's notifications.

**Authentication:** Required
**Status:** `200 OK`

**Response Body:**
```json
[
  {
    "id": 10000001,
    "type": "workout-like",
    "from_username": "friend_five",
    "profile_pic": "https://...",
    "date": "2024-01-15T18:30:00.000Z",
    "workout_id": "ec55f0ba-...",
    "workout_title": "Grwm"
  },
  {
    "id": 10000001,
    "type": "workout-comment",
    "from_username": "friend_three",
    "profile_pic": "https://...",
    "date": "2024-01-15T18:30:00.000Z",
    "workout_id": "ec55f0ba-...",
    "workout_title": "Ff wakker worden",
    "comment": "Goeiemorgen"
  },
  {
    "id": 10000001,
    "type": "accept-follow-request",
    "from_username": "jeronedepatser",
    "profile_pic": "https://...",
    "date": "2024-01-15T18:30:00.000Z"
  }
]
```

**Notification Types:**

| Type | Description | Extra Fields |
|------|-------------|-------------|
| `workout-like` | Someone liked your workout | `workout_id`, `workout_title` |
| `workout-comment` | Someone commented on your workout | `workout_id`, `workout_title`, `comment` |
| `accept-follow-request` | Someone accepted your follow request | (none) |

---

## 12. Push Notifications

### GET `/push_notification_settings`

Returns push notification settings.

**Authentication:** Required
**Status:** `200 OK`

### POST `/android_push_token`

Registers a Firebase Cloud Messaging (FCM) push token for the device.

**Authentication:** Required
**Status:** `200 OK`
**Response Body:** Empty

**Request Body:**
```json
{
  "token": "ebtyhUYCQHi2BGCiQ1BN_C:APA91bFMHe1SYksEARFjusS5b8bkw6mlV8mYAGcMFuBTOumr44VXYluLx8sB5GfEAyRKF0UKR5uPSxk4dIIHUJXUUIe1IWq4qVdHjrjD5orodFgbrYUylxI"
}
```

### DELETE `/android_push_token`

Unregisters the device's push token (called on logout).

**Authentication:** Required
**Status:** `200 OK`
**Response Body:** Empty

---

## 13. Body Measurements

### GET `/body_measurements`

Returns the user's body measurement data.

**Authentication:** Required
**Status:** `200 OK`

---

## 14. Plate Calculator

### GET `/plate_calculator_plate`

Returns the user's plate calculator plate configurations.

**Authentication:** Required
**Status:** `200 OK`

### GET `/plate_calculator_bar`

Returns the user's plate calculator bar configurations.

**Authentication:** Required
**Status:** `200 OK`

---

## 15. Subscription & Promotions

### GET `/user_subscription`

Returns the current user's subscription status.

**Authentication:** Required
**Status:** `200 OK`

### GET `/current_promo`

Returns any active promotional offers.

**Authentication:** Required
**Status:** `200 OK`
**Response:** Empty when no promo is active.

---

## 16. App Configuration

### GET `/minimum_app_version`

Returns the minimum required app version. Used to enforce app updates.

**Authentication:** API key only (no auth token required in some cases)
**Status:** `200 OK`

### GET `/enabled_remote_feature_flags`

Returns enabled feature flags for the client. Does NOT require auth token.

**Authentication:** API key only
**Status:** `200 OK`

### GET `/available_login_methods`

Returns available login/authentication methods.

**Authentication:** Required
**Status:** `200 OK`

### GET `/client_invites`

Returns pending client (coaching) invites for the user.

**Authentication:** Required
**Status:** `200 OK`

---

## 17. Analytics & Metadata

### POST `/user_metadata`

Sends device and user metadata to the server.

**Authentication:** Required
**Status:** `200 OK`
**Response Body:** Empty

**Request Body:**
```json
{
  "appLanguage": "en",
  "platform": "android",
  "platformVersion": "34",
  "appVersion": "3.1.11 - (3265149)",
  "securityId": "1771043426:daabfb41-...:9e601d92aa00c0aa",
  "googleAdId": "7fc3adcc-30cd-4a15-a9a3-8040e8a28f1a",
  "adjustAdId": "de78481ba67acb7c1b8a831dc198b0b7"
}
```

### POST `/network_info`

Reports the current network type to the server.

**Authentication:** Required
**Status:** `200 OK`
**Response Body:** Empty

**Request Body:**
```json
{
  "networkType": "wifi"
}
```

---

## 18. Data Models

### Workout Object

```json
{
  "id": "d440248b-f01e-40b7-a2c1-dc16721b4f55",
  "name": "Grwm",
  "index": 230554482,
  "media": [],
  "user_id": "ec55f0ba-...",
  "comments": [],
  "end_time": 1771135914,
  "short_id": "ezgBYIqVrPQ",
  "username": "example_user",
  "verified": false,
  "exercises": [/* Exercise objects */],
  "biometrics": {
    "total_calories": 227,
    "average_heart_rate": 134,
    "heart_rate_samples": [
      { "bpm": 92, "timestamp_ms": 1770873590000 }
    ]
  },
  "created_at": "2024-01-15T18:30:00.000Z",
  "image_urls": [],
  "is_private": false,
  "like_count": 2,
  "routine_id": "ec55f0ba-...",
  "start_time": 1771132981,
  "updated_at": "2024-01-15T18:30:00.000Z",
  "apple_watch": false,
  "description": "",
  "like_images": ["https://..."],
  "nth_workout": 210,
  "wearos_watch": false,
  "comment_count": 0,
  "profile_image": "https://...",
  "estimated_volume_kg": 3930.8,
  "include_warmup_sets": true,
  "is_biometrics_public": true,
  "preview_workout_likes": [
    {
      "username": "example_user",
      "profile_pic": "https://..."
    }
  ],
  "is_liked_by_user": true
}
```

| Field | Type | Description |
|-------|------|-------------|
| `id` | string (UUID) | Unique workout identifier |
| `name` | string | Workout name/title |
| `index` | number | Global sequential index (used for pagination) |
| `media` | array | Attached media objects `{url, type}` |
| `user_id` | string (UUID) | Owner's user ID |
| `comments` | array | Comment objects |
| `end_time` | number (unix) | Workout end time (unix timestamp in seconds) |
| `short_id` | string | Short shareable ID |
| `username` | string | Owner's username |
| `verified` | boolean | Whether the owner is verified |
| `exercises` | array | Array of Exercise objects |
| `biometrics` | object | Heart rate and calorie data |
| `biometrics.total_calories` | number | Total calories burned |
| `biometrics.average_heart_rate` | number | Average heart rate (BPM) |
| `biometrics.heart_rate_samples` | array | Array of `{bpm, timestamp_ms}` |
| `created_at` | string (ISO 8601) | When the workout was created |
| `image_urls` | array | Array of image URLs |
| `is_private` | boolean | Whether the workout is private |
| `like_count` | number | Number of likes |
| `routine_id` | string (UUID) \| null | Associated routine ID (if started from a routine) |
| `start_time` | number (unix) | Workout start time (unix timestamp in seconds) |
| `updated_at` | string (ISO 8601) | Last update timestamp |
| `apple_watch` | boolean | Whether workout was tracked with Apple Watch |
| `wearos_watch` | boolean | Whether workout was tracked with WearOS |
| `description` | string | Workout description |
| `like_images` | array | Profile pic URLs of users who liked |
| `nth_workout` | number | This user's nth workout (e.g., 210th workout) |
| `comment_count` | number | Number of comments |
| `profile_image` | string (URL) | Owner's profile thumbnail |
| `estimated_volume_kg` | number | Estimated total volume in kg |
| `include_warmup_sets` | boolean | Whether volume includes warmup sets |
| `is_biometrics_public` | boolean | Whether biometrics are publicly visible |
| `preview_workout_likes` | array | Preview of users who liked `{username, profile_pic}` |
| `is_liked_by_user` | boolean | Whether the requesting user has liked this workout |

### Exercise Object

```json
{
  "id": "ec55f0ba-...",
  "url": "https://pump-app.s3.eu-west-2.amazonaws.com/exercise-assets/....mp4",
  "sets": [/* Set objects */],
  "notes": "",
  "title": "Chest Fly (Machine)",
  "de_title": "Fliegende (Maschine)",
  "es_title": "Aperturas (Máquina)",
  "fr_title": "Écarté (Machine)",
  "it_title": "Croci (Macchina)",
  "ja_title": "チェストフライ（マシーン）",
  "ko_title": "체스트 플라이 (머신)",
  "pt_title": "Crucifixo no Voador (Máquina)",
  "ru_title": "Разводка (Тренажёр)",
  "tr_title": "Chest Fly (Makine)",
  "zh_cn_title": "飞鸟夹胸（机）",
  "zh_tw_title": "飛鳥夾胸（機）",
  "priority": 0,
  "media_type": "video",
  "superset_id": null,
  "muscle_group": "chest",
  "rest_seconds": 0,
  "exercise_type": "weight_reps",
  "other_muscles": [],
  "thumbnail_url": "https://...jpg",
  "equipment_category": "machine",
  "exercise_template_id": "78683336",
  "volume_doubling_enabled": false,
  "custom_exercise_image_url": null
}
```

| Field | Type | Description |
|-------|------|-------------|
| `id` | string (UUID) | Unique exercise instance ID |
| `url` | string (URL) | Exercise demo video URL |
| `sets` | array | Array of Set objects |
| `notes` | string | Exercise-specific notes |
| `title` | string | Exercise name (English) |
| `{lang}_title` | string \| null | Localized exercise names (de, es, fr, it, ja, ko, pt, ru, tr, zh_cn, zh_tw) |
| `priority` | number | Display priority |
| `media_type` | string | Type of demo media: `"video"` |
| `superset_id` | number \| null | Superset group identifier (null if not in a superset) |
| `muscle_group` | string | Primary muscle group (see Enums below) |
| `rest_seconds` | number | Rest timer between sets (0 = disabled) |
| `exercise_type` | string | Exercise type (see Enums below) |
| `other_muscles` | array of strings | Secondary muscle groups |
| `thumbnail_url` | string (URL) \| null | Exercise thumbnail image URL |
| `equipment_category` | string | Equipment type (see Enums below) |
| `exercise_template_id` | string | Template reference (hex ID or UUID for custom) |
| `volume_doubling_enabled` | boolean | Whether to double volume (for unilateral exercises) |
| `custom_exercise_image_url` | string \| null | Custom user-uploaded exercise image |

### Set Object

```json
{
  "id": "10000001",
  "prs": [],
  "rpe": null,
  "reps": 13,
  "index": 0,
  "indicator": "normal",
  "weight_kg": 70,
  "completed_at": "2024-01-15T18:30:00.000Z",
  "custom_metric": null,
  "distance_meters": null,
  "personalRecords": [],
  "duration_seconds": null
}
```

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique set identifier |
| `prs` | array | Personal records achieved in this set |
| `prs[].type` | string | PR type: `"best_weight"`, `"best_1rm"`, `"best_duration"`, `"best_distance"` |
| `prs[].value` | number | PR value |
| `rpe` | number \| null | Rate of Perceived Exertion (1-10 scale) |
| `reps` | number \| null | Number of repetitions |
| `index` | number | Set order index (0-based) |
| `indicator` | string | Set type: `"normal"`, `"warmup"`, `"dropset"`, `"failure"` |
| `weight_kg` | number \| null | Weight in kilograms |
| `completed_at` | string (ISO 8601) | When the set was completed |
| `custom_metric` | number \| null | Custom metric value |
| `distance_meters` | number \| null | Distance in meters (for cardio exercises) |
| `personalRecords` | array | Confirmed personal records |
| `duration_seconds` | number \| null | Duration in seconds (for timed exercises) |

### Comment Object

```json
{
  "id": 10000001,
  "comment": "Goeiemorgen",
  "username": "friend_three",
  "verified": false,
  "full_name": "Example Name",
  "created_at": "2024-01-15T18:30:00.000Z",
  "like_count": 0,
  "profile_pic": "https://...",
  "is_liked_by_user": false,
  "parent_comment_id": null
}
```

| Field | Type | Description |
|-------|------|-------------|
| `id` | number | Comment ID |
| `comment` | string | Comment text (supports @mentions like `@username`) |
| `username` | string | Commenter's username |
| `verified` | boolean | Whether commenter is verified |
| `full_name` | string | Commenter's display name |
| `created_at` | string (ISO 8601) | Comment timestamp |
| `like_count` | number | Number of likes on the comment |
| `profile_pic` | string (URL) | Commenter's profile picture |
| `is_liked_by_user` | boolean | Whether the requesting user has liked this comment |
| `parent_comment_id` | number \| null | Parent comment ID for threaded replies |

### Enums

**Exercise Types:**
| Value | Description |
|-------|-------------|
| `weight_reps` | Weight and repetitions (e.g., Bench Press) |
| `reps_only` | Repetitions only, no weight (e.g., Pull-ups) |
| `duration` | Duration only (e.g., Plank) |
| `distance_duration` | Distance and duration (e.g., Running) |

**Muscle Groups:**
| Value |
|-------|
| `chest` |
| `shoulders` |
| `biceps` |
| `triceps` |
| `lats` |
| `upper_back` |
| `abdominals` |
| `quadriceps` |
| `hamstrings` |
| `glutes` |
| `forearms` |
| `cardio` |
| `other` |

**Equipment Categories:**
| Value |
|-------|
| `barbell` |
| `dumbbell` |
| `machine` |
| `kettlebell` |
| `resistance_band` |
| `none` |

**Set Indicators:**
| Value | Description |
|-------|-------------|
| `normal` | Standard working set |
| `warmup` | Warm-up set |
| `dropset` | Drop set |
| `failure` | Set to failure |

**Following Status:**
| Value | Description |
|-------|-------------|
| `not-following` | Not following the user |
| `following` | Currently following |
| `pending` | Follow request pending (private accounts) |

**Personal Record Types:**
| Value | Description |
|-------|-------------|
| `best_weight` | Heaviest weight used |
| `best_1rm` | Best estimated one-rep max |
| `best_duration` | Longest duration |
| `best_distance` | Longest distance |

---

## 19. Discovered Undocumented Endpoints

> These endpoints were discovered through systematic API probing and are not visible in standard app traffic.

### POST `/login_with_saved_account`

Re-authenticates using a saved userId + secret pair (device-stored credentials). Returns fresh tokens without requiring email/password.

**Authentication:** API key only (no bearer token needed)
**Status:** `200 OK`

**Request Body:**
```json
{
  "userId": "ec55f0ba-b60d-4da7-a0d7-fa75572e2d2d",
  "secret": "<redacted>"
}
```

**Response Body:**
```json
{
  "auth_token": "a5c8524a-fe13-467f-a63a-62ebe0a689fa",
  "user_id": "ec55f0ba-b60d-4da7-a0d7-fa75572e2d2d",
  "access_token": "<redacted>",
  "refresh_token": "<redacted>",
  "expires_at": "2024-01-15T18:30:00.000Z"
}
```

### GET `/users/search?q={query}`

Search for users by username. Returns up to ~50 results. The `q` parameter matches against usernames (prefix search). The `limit` query parameter does NOT appear to be respected (always returns full results).

**Authentication:** Required
**Status:** `200 OK`

**Response Body:**
```json
[
  {
    "id": "ec55f0ba-...",
    "profile_pic": "https://...",
    "username": "example_user",
    "verified": false,
    "full_name": "",
    "following_status": "not-following",
    "private_profile": false
  }
]
```

### GET `/users/{username}`

Look up a user by exact username. Returns an array (typically with one element).

**Authentication:** Required
**Status:** `200 OK`

**Response Body:** Same schema as `/users/search` results.

### GET `/followers/{username}`

Returns the full list of a user's followers.

**Authentication:** Required
**Status:** `200 OK`

**Response Body:**
```json
[
  {
    "id": "ec55f0ba-...",
    "username": "friend_four",
    "verified": false,
    "full_name": null,
    "following_status": "following",
    "private_profile": false
  }
]
```

### GET `/following/{username}`

Returns the full list of users that a user follows. Same response schema as `/followers/{username}`.

**Authentication:** Required
**Status:** `200 OK`

### GET `/workout_likes/{workout_id}`

Returns the full list of users who liked a specific workout, with more detail than the `preview_workout_likes` field in the workout object.

**Authentication:** Required
**Status:** `200 OK`

**Response Body:**
```json
[
  {
    "id": "ec55f0ba-...",
    "profile_pic": "https://...",
    "username": "friend_five",
    "verified": false,
    "full_name": "Example Name",
    "following_status": "following",
    "private_profile": false
  }
]
```

### GET `/workout_comments/{workout_id}`

Returns comments for a workout as a standalone endpoint (separate from the `comments` array embedded in the workout object). Useful for refreshing comments without re-fetching the entire workout.

**Authentication:** Required
**Status:** `200 OK`

**Response Body:** Array of Comment objects (same schema as embedded comments).

### GET `/routine/{routine_id}`

Fetches a single routine by its UUID. Returns the routine wrapped in a `{"routine": {...}}` object, with full exercise details including localized titles, set templates, and media URLs.

**Authentication:** Required
**Status:** `200 OK`

**Response Body:**
```json
{
  "routine": {
    "id": "ec55f0ba-...",
    "title": "Hardlopen",
    "username": "example_user",
    "profile_pic": "https://...",
    "exercises": [/* full exercise objects with sets */],
    "updated_at": "2024-01-15T18:30:00.000Z",
    "parent_routine_id": null
  }
}
```

### GET `/workout_count`

Returns the authenticated user's total workout count.

**Authentication:** Required
**Status:** `200 OK`

**Response Body:**
```json
{"workout_count": 210}
```

### GET `/push_notification_settings`

Returns granular push notification settings (more detailed than the account-level flags).

**Authentication:** Required
**Status:** `200 OK`

**Response Body:**
```json
{
  "comment_replies": true,
  "comment_likes": true,
  "comment_discussion": true,
  "comment_mention": true,
  "comment_on_workout": true,
  "follows": true,
  "likes": true,
  "monthly_report": true
}
```

### GET `/user_key_values`

Returns a key-value store of user-specific app settings and state. Used by the client to persist UI preferences, notification read state, and feature dismissals.

**Authentication:** Required
**Status:** `200 OK`

**Response Body:**
```json
{
  "UPDATED_AT": "2024-01-15T18:30:00.000Z",
  "SetCompleteVolume": "off",
  "HIDE_HEVY_COACH_LAUNCH_FEED_CELL": true,
  "EXERCISE_DETAIL_IS_SET_RECORDS_EXPANDED": true,
  "HAS_DISMISSED_CALENDAR_MULTI_YEAR_CELL": true,
  "NOTIFICATION_STORE_LAST_NOTIFICATION_RECEIVED": "2024-01-15T18:30:00.000Z",
  "NOTIFICATION_STORE_LAST_READ": "2024-01-15T18:30:00.000Z",
  "HAS_DISMISSED_MONTHLY_REPORT_CELL_11_2025": true,
  "MonthlyReportPushEnabled": true
}
```

### GET `/enabled_remote_feature_flags` (expanded docs)

Returns feature flags as `{"flags": [...]}` (not a bare list). Observed flags include:

| Flag | Description |
|------|-------------|
| `onboarding_how_did_you_hear` | Show onboarding survey |
| `enable_streaks_abcd_test` | A/B test for streak feature |
| `enable_login_recaptcha` | Enable reCAPTCHA on login |
| `disable_streaks_experience` | Disable streak UI |
| `bypass_sensitive_api_verification` | Skip sensitive API verification |
| `disable_calendar_multi_year_feed_cell` | Disable multi-year calendar cell |

### GET `/custom_exercise_templates` (expanded docs)

Response includes additional fields not previously documented:

| Field | Type | Description |
|-------|------|-------------|
| `is_custom` | boolean | Always `true` for user-created exercises |
| `is_archived` | boolean | Whether the exercise is archived/hidden |
| `priority` | number | Display priority (default: 10) |
| `custom_exercise_image_url` | string \| null | User-uploaded exercise image |
| `thumbnail_url` | string \| null | Thumbnail of custom image |

---

## CDN & Media URLs

| Service | Domain | Usage |
|---------|--------|-------|
| CloudFront CDN | `d2l9nsnmtah87f.cloudfront.net` | Profile images, user-uploaded media |
| S3 (Exercise Assets) | `pump-app.s3.eu-west-2.amazonaws.com` | Exercise demo videos and thumbnails |
| Google Photos | `lh3.googleusercontent.com` | Profile pictures from Google OAuth |

---

## Rate Limiting & Notes

- No explicit rate limiting headers were observed.
- The API heavily uses ETags and conditional requests to reduce bandwidth.
- Timestamps use two formats: ISO 8601 strings and Unix timestamps (seconds).
- All workout volumes are in kilograms (regardless of user preference).
- The `index` field on workouts is a global auto-incrementing counter used for pagination/ordering.
- The `short_id` field is used for shareable workout links.
- Profile images use CloudFront CDN with `-thumbnail` suffixed URLs for smaller versions.

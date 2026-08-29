# Coaching workflows

Seven prompts that turn Hevy data into coaching output. Each names the calls it
needs, the sections it should produce, and where the obvious implementation gets
the maths wrong.

`references/workflows.md` has the mechanical recipes these build on. Everything
here runs on the v1 public API unless it says otherwise.

## Review one workout

Input: a workout id.

`GET /v1/workouts/{id}`, then report:

1. Overview: title, date, duration from `end_time` minus `start_time`, total volume.
2. Per exercise: every set as weight and reps, with the best set marked.
3. Volume by muscle group, resolved through the template cache.
4. Any PRs, checked against that exercise's history rather than against the session.
5. Feedback tied to specific sets, not general advice.
6. Rest assessment. The v1 workout body carries no rest data, so this is inferred
   from exercise type and must be labelled as a suggestion.

Report in the athlete's own unit system. Hevy stores kilograms, so a pounds user
needs conversion at the edge, not in the middle of the analysis.

## Weekly summary

Input: a date range, usually the last seven days.

Crawl `/v1/workouts` for the window, then combine the counting recipes:

1. Total workouts, volume and duration.
2. Weekly sets per muscle group against the athlete's target range.
3. Volume trend across the window.
4. PRs set this week.
5. Recovery read from frequency and volume together. Four heavy sessions is not the
   same load as four light ones.
6. What to change next week, with a deload flagged if the check below says so.

## Exercise progression

Input: a username and an exercise.

Resolve the exercise to a template id, then `GET /v1/exercise_history/{id}`. Crawling
workout pages and filtering client side also works and costs far more requests.

1. Session table: date, sets, best set.
2. Estimated 1RM per session, Epley, `weight_kg * (1 + reps / 30)`.
3. Volume per session.
4. When each PR landed.
5. Plateau check, using the stall rule in workflows.md so a volume cut is not read
   as a stall.
6. What to change, from the data rather than from general programming advice.

## Deload check

Input: a username.

Read the last 15 to 20 sessions and answer four questions: has volume stayed high
for several weeks, is training frequency leaving rest days, are lifts stalling or
going backwards, and how many hours a week is the athlete training.

Return a yes or no, a confidence, and if yes the type (volume, intensity, or full
rest), a duration, and how to build back up.

State the evidence next to the verdict. "Deload, bench and squat e1RM both down two
sessions running while weekly sets went up 20 percent" is a claim someone can argue
with. "You seem fatigued" is not.

## Program suggestion

Input: a username and a goal, for example strength, hypertrophy, fat loss or general
fitness.

Read the last 20 workouts, the muscle group distribution, the training frequency and
the existing routines. Then design a programme that:

- uses exercises the athlete already has history on, so every weight is anchored
- fixes the biggest gaps in muscle group coverage
- fits the frequency they actually train, not the frequency they aspire to
- states progression rules, rest periods and RPE targets
- runs four weeks

Then write each day into Hevy with `POST /v1/routines`, one routine per day, grouped
in a folder created with `POST /v1/routine_folders`. Rest defaults of 150 seconds for
compounds and 90 for isolation are a reasonable start.

Remember the routine payload rules. Sets take `type` and `rep_range`, never `rpe`,
and `rest_seconds` sits on the exercise. Put the reasoning in the routine `notes`.

## Social activity

Needs the internal API. v1 has no social endpoints at all.

Follower and following counts, recent notifications, and likes and comments per
workout. From those: an engagement rate, the workout that drew the most response,
and who interacts most often.

## Compare two athletes

Needs the internal API for anything about another user. v1 only reaches your own
account.

Profiles and ten recent workouts each, compared on workout count, average volume,
muscle group focus, exercise selection and weekly frequency.

Comparing two people's training is mostly a way to produce a confident wrong answer.
Different bodyweights, heights, training ages and goals make average volume close to
meaningless as a ranking. Report the numbers and say what they do not account for.

## Two mistakes to avoid when implementing these

**Do not detect a volume trend by splitting the window in half and comparing the two
averages.** One heavy session flips the verdict, and the answer changes depending on
whether the window holds an even or odd number of workouts. Fit a slope across the
sessions, or compare a rolling average against the one before it.

**Do not credit only the primary muscle group.** Set counts per muscle come out
badly wrong if secondary work is dropped, because most compound lifts carry two or
three secondary groups. Credit `primary_muscle_group` a full set and each entry of
`secondary_muscle_groups` a fraction, and name the fraction you chose.

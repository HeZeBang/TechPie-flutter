# ROADMAP

This file provides an overview of the direction this project is heading. The roadmap is organized in steps that focus on a specific theme,for instance, UX.

## M1 - Adoption and First Login

This phase measures monthly usage and follows new installations from first launch to first successful login.

- Let users opt in to telemetry. Use a random per-installation identifier for counting. Keep student IDs, account names and user content out of events.
- Report store installs where the distributor provides them. Show first launches from participating installations as a separate count.
- For each weekly group of first launches, show how many and what percentage completed a first login within seven days.
- Report monthly active users as distinct participating installations that opened TechPie in the past 30 days. Count each installation once, including activity before login.

## M2 - Feature Usage and Feedback

This phase shows which features students use each day and where feedback gets lost between opening the form and sending it.

- Show daily unique users for each feature, counting each participating installation once per feature per day.
- Count feedback forms opened, forms submitted successfully, and submissions that returned an error. A successful retry counts as one delivered report.
- Among forms still undelivered after 24 hours, distinguish forms with no submission attempt from forms with a failed or unconfirmed attempt.

## M3 - Lecture Recording Reliability

This phase uses lecture recordings to identify problems that usage counts alone can hide. Start timing when a user opens the feature.

- Show the count and percentage of visits with an error in the first 10 seconds, alongside the number of distinct installations affected.
- Show the count and percentage of visits that end within 30 seconds. Break these down by whether the recording list loaded or an error appeared before exit.
- Measure time to the first usable recording list. Compare median and 95th-percentile load times and error rates by app version and platform to spot regressions.




# TEMPLATE
## [M0 - Basic Infrastructure](https://github.com/Dovyski/template/milestone/1)

In this phase of the project the focus is on X, Y and Z. The expected features are:

- Something the user can do.
- Description of a feature.
- Ability to save things.
- Etc.

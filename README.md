# DATACLIPS Y3K
a demo app to showcase a potential new architecture for Heroku Dataclips

## How it might work

- provision request: `heroku addons:create heroku-dataclips:shield -a myshieldapp -- --datasource=my-shield-db`
- Shogun receives the provision POST request to `heroku/resources` endpoint
- DataclipsProvisioner mediator creates a DataclipsInstance
- DataclipsInstance creates a HerokuApp

### Prerequisites
- a Heroku app with an attached Postgres addon

### Trying it out
- clone this repository
- `heroku apps:create heroku-dataclips-y3k-test`
  - optionally include the -s <space> flag if your target app is in a Private or Shield Space
- `heroku addons:attach <addon-name> -a heroku-dataclips-y3k-test --as DATABASE_URL`
- `git push heroku main`
- `heroku run 'bundle exec rake db:migrate' -a heroku-dataclips-y3k-test`
- `heroku apps:open -a heroku-dataclips-y3k-test`
- make some dataclips!
# node-builder
Waffle.io's builder image

### Purpose
* Utilizes circleci's nodejs image and adds our dependencies required for
  deploying our applications
* The goal would be to limit the amount of time spent waiting on installing
  dependencies not required for our application
* Also brings in the required deployment script `deploy.sh` that is used across
  all of our applications


## Deploying Applications
### The `deploy.json` file
* This file should live in the repo for which we are deploying the application
  from
* Here's an example:

```json
{
  "app_name": "app",
  "deployment_name": "deploy",
  "image_name": "waffle.io/app",
  "branch": [
    {
      "cluster": {
        "name": "develop",
        "project": "waffleio-dev"
      },
      "name": "dev",
      "deploy_branch": true
    },
    {
      "cluster": {
        "name": "staging",
        "project": "waffleio-stage"
      },
      "name": "staging1",
      "deploy_branch": true,
      "deploy_dev": false,
      "newrelic_id": "0123456",
      "tag_latest": false
    },
    {
      "cluster": {
        "name": "production",
        "project": "waffleio-production"
      },
      "name": "master",
      "deploy_branch": true,
      "deploy_dev": true,
      "newrelic_id": "0123456",
      "tag_latest": true
    }
  ]
}

```

### CI
* Then in our ci, simply execute `deploy`

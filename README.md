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

## Updating this image
We maintain two separate base builder images `waffleio/node-builder:<version>` and `waffleio/node-builder:<version>-browsers`. The version tag matches the version of of the CircleCI node image we are using. So if we are using `circleci/node:8.11.3` then we tag our image as `waffleio/node-builder:8.11.3`. Likewise, for the `circleci/node:8.11.3` then we tag our image as `waffleio/node-builder:8.11.3`.

### Testing changes to this image
As with any of our repos, changes should be pushed to a branch. Quay will automatically build an image for that branch and tag it with the branch name and then you can update one of the other repos to use that tag. So, let's assume your branchname is `updates`. Here are the steps to test it:
1. Make and commit your changes to this image
1. `git push origin HEAD:updates`
1. Wait for the Quay build to finish
1. Go to a repo that uses this base image (the api for example) and inside of the circle.yml change the build image to be the new one from your branch (notice the `updates`):
    ```yml
    docker:
          - image: quay.io/waffleio/node-builder:updates
    ```
1. Push that repo to a branch and the circle build will pull the `updates` builder image

### Releasing official changes
Because we must maintain two versions of this image (the basic one and then the browsers one) this is a manual process. Once a PR is merged to master, you will have to go into Quay and add the version tag to the new master version. If that tag already exists (which it will unless you changed the `FROM` image in the Dockerfile), it is fine, it will just move it to the new master. Now, you have to build the browsers version. Here are the steps to do that:
1. `git checkout master && git pull` to make sure you have the new changes you just pushed
1. Open the Dockerfile and change `FROM circleci/node:<version>` to `FROM circleci/node:<version>-browsers`
1. `git push origin HEAD:update-browsers` (the branch name can be anything)
1. Wait for Quay to build the image for that new branch 
1. Add/move the `<version>-browsers` tag to that new branch

### Using the updated image in our other repos
If the version did not change, you should not have to change anything in the other repos. If the version did change, that means the other repos will need to pull the new version. To do that, go to the circle.yml in the repo and change this line:
```yml
docker:
      - image: quay.io/waffleio/node-builder:<version>
```
to have the new `version`.

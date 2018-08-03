#!/bin/bash

activate_ci_kubernetes_account () {
  echo "Activating gcloud for ${cluster} on project ${project}"
  case ${cluster} in
    "production")
      echo ${PROD_GCLOUD_SERVICE_KEY} | base64 --decode --ignore-garbage > ${HOME}/gcloud-service-key.json
      ;;
    *)
      echo ${DEV_GCLOUD_SERVICE_KEY} | base64 --decode --ignore-garbage > ${HOME}/gcloud-service-key.json
      ;;

  esac
  gcloud auth activate-service-account --key-file ${HOME}/gcloud-service-key.json
  gcloud config set project ${project}
  gcloud container clusters get-credentials ${cluster} --zone us-east4-a
}

gh_deployment_create_body () {
  cat <<EOD
{
  "ref": "${CIRCLE_SHA1}",
  "environment": "${environment}",
  "required_contexts": [],
  "auto_merge": false
}
EOD
}

create_gh_deployment () {
  if [[ ${GITHUB_ACCESS_TOKEN} == "" ]]
  then
    echo "Environment variable GITHUB_ACCESS_TOKEN not provided."
  else
    curl -s -X POST "https://api.github.com/repos/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}/deployments" \
      -H 'Content-Type: application/json' \
      -H 'Accept: application/vnd.github.ant-man-preview+json' \
      -u "waffle-cicd-bot:${GITHUB_ACCESS_TOKEN}" \
      -d "$(gh_deployment_create_body)"
  fi
}

notify_gh_about_a_deployment () {
  if [[ ${GITHUB_ACCESS_TOKEN} == "" ]]
  then
    echo "Environment variable GITHUB_ACCESS_TOKEN not provided."
  else
    declare -r deployment_id=${1}
    declare -r deployment_status=${2}
    curl -s -X POST "https://api.github.com/repos/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}/deployments/${deployment_id}/statuses" \
      -H 'Content-Type: application/json' \
      -H 'Accept: application/vnd.github.ant-man-preview+json' \
      -u "waffle-cicd-bot:${GITHUB_ACCESS_TOKEN}" \
      -d "$(gh_deployment_notify_body $deployment_status)" > /dev/null
  fi
}

gh_deployment_notify_body () {
  declare -r deployment_status=${1}
  if [[ ${environment} == "production" ]]
  then
    environment_url="https://waffle.io"
  else
    environment_url="https://${environment}.waffle.io"
  fi
  cat <<EOD
{
  "state": "${deployment_status}",
  "log_url": "${CIRCLE_BUILD_URL}",
  "environment_url": "${environment_url}"
}
EOD
}

slack_body () {
  case $1 in
    success)
      declare -r deploy_status='Successful'
      declare -r color='00aa00'
      declare -r emoji=':grinning:'
      ;;
    fail)
      declare -r deploy_status='Failed'
      declare -r color='aa0000'
      declare -r emoji=':sob:'
      ;;
  esac

  cat <<EOD
{
  "text": "${deploy_status} <${CIRCLE_BUILD_URL}|Deploy> of <https://github.com/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}/commit/${CIRCLE_SHA1}|${CIRCLE_SHA1}>",
  "username": "deploy.sh",
  "icon_emoji": "${emoji}",
  "attachments": [
  {
    "color": "${color}",
    "fields": [
    {
      "title": "App",
      "value": "${deployment_name}-${environment}",
      "short": true
    },
    {
      "title": "Who",
      "value": "${CIRCLE_USERNAME}",
      "short": true
    },
    {
      "title": "Circle Build",
      "value": "<${CIRCLE_BUILD_URL}|${CIRCLE_BUILD_NUM}>",
      "short": true
    }
    ]
  }
  ]
}
EOD
}

notify_slack_about_a_release () {
  if [[ ${SLACK_WEBHOOK_URL} == "" ]]
  then
    echo "Environment variable SLACK_WEBHOOK_URL not provided."
  else
    curl -s -X POST ${SLACK_WEBHOOK_URL} \
      -H 'Content-Type: application/json' \
      -d "$(slack_body $1)" > /dev/null
  fi
}

newrelic_body () {
  cat <<EOD
{
  "deployment": {
    "revision": "${CIRCLE_SHA1}",
    "user": "${CIRCLE_USERNAME}"
  }
}
EOD
}

notify_newrelic_about_a_release () {
  case ${environment} in
    "production")
      if [[ ${PROD_NEWRELIC_API_KEY} != "" ]]
      then
        declare -r new_relic_token=${PROD_NEWRELIC_API_KEY}
      else
        declare -r new_relic_token=${NEWRELIC_API_KEY}
      fi
      ;;
    *)
      if [[ ${DEV_NEWRELIC_API_KEY} != "" ]]
      then
        declare -r new_relic_token=${DEV_NEWRELIC_API_KEY}
      else
        declare -r new_relic_token=${NEWRELIC_API_KEY}
      fi
      ;;
  esac
  if [[ ${new_relic_token} == "" ]]
  then
    echo "Environment variable *NEWRELIC_API_KEY not provided."
  else
    curl -s -X POST "https://api.newrelic.com/v2/applications/${newrelic_app_id}/deployments.json" \
      -H "X-Api-Key:${new_relic_token}" \
      -H 'Content-Type: application/json' \
      -d "$(newrelic_body)" > /dev/null
  fi
}

tag_docker_release () {
  docker tag ${image_name}:${CIRCLE_SHA1} ${image_name}:latest
  docker push ${image_name}:latest
}

deploy () {
  if [[ ${environment} != "dev" ]]
  then
    declare -r gh_deploy_id=$(create_gh_deployment | jq .id)
  fi

  echo "Deploying to ${environment}"
  kubectl set --namespace ${environment} image deployments/${deployment_name} ${container_name}=${image_name}:${CIRCLE_SHA1} --record
  kubectl rollout status deployments/${deployment_name} --namespace ${environment}
  if [[ $? != 0 ]]
  then
    echo "The deploy has failed, I'm going to attempt to roll back..."
    kubectl rollout undo deployments/${deployment_name} --namespace ${environment}
    kubectl rollout status deployments/${deployment_name} --namespace ${environment}
    if [[ $? != 0 ]]
    then
      echo "Rollback was unsuccessful."
    else
      echo "Rollback was successful."
    fi

    notify_slack_about_a_release fail
    notify_gh_about_a_deployment $gh_deploy_id "failure"
    exit 1
  else
    echo "Deployment has succeeded."
    notify_slack_about_a_release success
    if [[ ${environment} != "dev" ]]
    then
      notify_gh_about_a_deployment $gh_deploy_id "success"
      notify_newrelic_about_a_release
    fi
  fi
}

main () {
  if [[ ! -e deploy.json ]]
  then
    echo "Missing a deploy.json file.  Exiting..."
    exit 1
  fi

  declare -r container_name=$(jq -r .app_name deploy.json)
  declare -r deployment_name=$(jq -r .deployment_name deploy.json)
  declare -r image_name=$(jq -r .image_name deploy.json)
  if [[ ${CIRCLE_BRANCH} == "master" ]]
  then
    declare environment="production"
  else
    declare environment=${CIRCLE_BRANCH}
  fi

  declare -r should_i_tag=$(jq ".branch[] | select(.name == \"${CIRCLE_BRANCH}\") | .tag_latest" deploy.json)
  declare -r should_i_deploy=$(jq ".branch[] | select(.name == \"${CIRCLE_BRANCH}\") | .deploy_branch // false" deploy.json)
  declare cluster=$(jq -r ".branch[] | select(.name == \"${CIRCLE_BRANCH}\") | .cluster.name" deploy.json)
  declare project=$(jq -r ".branch[] | select(.name == \"${CIRCLE_BRANCH}\") | .cluster.project" deploy.json)
  declare -r newrelic_app_id=$(jq -r ".branch[] | select(.name == \"${CIRCLE_BRANCH}\") | .newrelic_id" deploy.json)
  declare -r should_do_a_dev_deploy=$(jq ".branch[] | select(.name == \"${CIRCLE_BRANCH}\") | .deploy_dev" deploy.json)

  if [[ ${should_i_tag} == "true" ]]
  then
    tag_docker_release
  fi

  if [[ ${should_i_deploy} == "true" ]]
  then
    activate_ci_kubernetes_account
    deploy
  else
    echo "Skipping deploy..."
  fi

  if [[ ${should_do_a_dev_deploy} == "true" ]]
  then
    declare environment=dev
    declare cluster=$(jq -r ".branch[] | select(.name == \"${environment}\") | .cluster.name" deploy.json)
    declare project=$(jq -r ".branch[] | select(.name == \"${environment}\") | .cluster.project" deploy.json)
    activate_ci_kubernetes_account
    deploy
  fi
}

main

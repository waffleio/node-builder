FROM circleci/node:8.11.4

ADD deploy.sh /bin/deploy

RUN set -x \
  && sudo apt-get update && sudo apt-get upgrade -y && sudo apt-get -y install apt-transport-https curl \
  && echo "deb https://packages.cloud.google.com/apt cloud-sdk-xenial main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list \
  && curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add - \
  && sudo apt-get update && sudo apt-get -y install google-cloud-sdk kubectl

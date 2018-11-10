# Run Travis in Your Kubernetes Cluster

Travis is a great CI software, and quite famous in community. Most of the travis
software, ie microservices are opensource. Some are not. This blogpost explores
how to setup these microservices on your kubernetes cluster, and get a copy of
travis running.

TL;DR: `helm install --name=travis bored-im/travis-helm`

### Overall archictecture

Travis has got following pieces:

- postgresql (for obvious reasons, data persistence, logs persistence)
- rabbitmq (for microservices to communicate)
- redis (for running background jobs using sidekiq)
- web (ember app which gives look and feel of travis UI)
- api (backend for web)
- listener (listen to github events)
- gatekeeper (creates builds to be executed) - ** Not opensourced **
- scheduler (schedules jobs based on organization limits)
- hub (maintains states, updates job and build statues)
- build (converts job config to shell script that can be run)
- worker (runs jobs)
- logs (collects logs from worker for jobs, aggregates them)

todo: image here

Lets dig into several pieces which come together now. I will be referring to
forks of repos I've done so that its easier to describe workarounds and
blockers.

All the forks are here https://github.com/bored-im and all the docker images
are here https://hub.docker.com/r/boredim/

### Travis Web

This is ember app which can be found here https://github.com/bored-im/travis-web
App is already dockerized, so not much tweaks are required. I had to fix
ruby version, and fix command to run puma.

Interesting thing is how travis manages configs across microservices. It has
a ruby gem https://github.com/travis-ci/travis-config which goes through
yaml file placed in `config` folder, goes through env variables and configures
microservice. Also each microservice provides set of defaults which will
be overridden by this gem. So, code is not cluttred with env variables.

### Travis Api

Sinatra app which exposes APIs to be consumed by web. This microservice is not
dockerized. So added Dockerfile, fixed unicorn, disabled ssl at middleware level.
Not many hacks here though. Changes can be found here
https://github.com/bored-im/travis-web

### Travis Listener

Again a sinatra app. Hooks installed in Github will point to this app. Once this
app recieves an event, it forwards that event to Gatekeeper. It simply puts the
event in redis, and Gatekeeper picks it up, and processes it.  This app is not
dockerized, so added Dockerfile. Changes can be found here
https://github.com/bored-im/travis-listener/

### Travis Gatekeeper

This microservice is the heart of travis infra. What needs to be done when a PR
is opened, when a commit is pushed, whether build has to be created with jobs, all
that logic goes here. Sadly its not opensource, which is understandable. Ive
created a minified version of this which needs to be improved based on settings
of a project, but it works whenever a commit is pushed. Code can be found here
https://github.com/bored-im/travis-bae

### Travis Scheduler

This microservice is responsible for figuring out limits of organizations, and
or users, and then schedule builds with jobs. If a user has hit a maximum
number of parallel jobs, scheduler won't create any further jobs until existing
jobs are completed. This app is not dockerized, so added Dockerfile, downgraded
from sidekiq-pro to sidekiq. Changes can be found here:
https://github.com/travis-ci/travis-scheduler/

### Travis Hub

Responsible for managing states, and updating status of builds and jobs. Here
downgraded sidekiq-pro to sidekiq, fixed Dockerfile. Changes can be found here:
https://github.com/bored-im/travis-hub/

### Travis Build

This microservice is responsible for converting `.travis.yml` to a bash script
which can be run by workers. Workers provide job config to travis build, and
this module will give a bash script. Changes can be found here:
https://github.com/bored-im/travis-build/

### Travis Worker

This is a go binary which recieves jobs from scheduler, analyzes those jobs,
generates bash script using build service, and then executes bash script. It
also streams logs for aggregation. By default, worker will pull in custom
docker image with all services from travis registry, and runs bash script
in the context of docker image. These images are not publicly available.
So, Ive modified Dockerfile such that services are installed as part of
worker itself, and bash script is run as part of worker container. Changes
can be found here: https://github.com/bored-im/worker/

### Travis Logs

This microservice is responsible for receiving logs from worker, aggregating
them, and then uploading them to S3. I have disabled S3 uploads for now,
fixed migrations, and redis url. This service uses sqitch for database
migrations, which is quite odd! Didn't like it that much being in Rails world.
Changes can be found here: https://github.com/bored-im/travis-logs/

### Travis Tasks

This microservice is responsible for posting slack notifications, sending
emails etc. Haven't worked on this yet.

### The Flow

With all these modules falling in place, a typical flow would be like this:


- Developer pushes code to github, or raises a PR
- Github sends event to travis listener.
- Listener receives event, enqueues a job in redis for sidekiq from other
  microservices to process
- Sidekiq of Travis bae (Gatekeeper) picks up the event, and evaluates it.
  If event matches repository settings in travis, bae will create a build
  and creates job(s) to be processed in database.
- Travis scheduler will be polling databases for jobs created, and if
  found, will pick them up, and pushes job to worker via rabbitmq.
- Travis worker picks up a job, contacts travis build to convert job into
  a bash script. Worker then picks up bash script and executes it. We
  ensure that docker image for worker contains all services required for
  running bash script.
- While running the script, or upon completion of script, worker closely
  monitors logs of script, and pushes them to rabbitmq for travis logs
  to process. In addition to that, worker also pushes status of jobs
  to rabbitmq for travis hub to process
- Travis hub picks up status from rabbitmq, updates job and build status
  in database. It is also responsible for re-queueing jobs sometimes.
- Travis logs picks up logs from worker, and stores them in database.
  Later background job will run to aggregate logs, and push them to S3.
  Right now, aggregator is disabled!
- Travis api glues lifecycle of a build and job(s) to web interface. It
  also uses pusher to send live updates to web interface. Pusher is not
  setup at the moment.
- We also have travis tasks to send emails, slack notifications etc. Its
  not setup as of now.

![Architecture](/architecture.svg)

Note that Redis is always used to process events drained from database or
rabbitmq.

### Get it working on your cluster

All the apps are dockerized, and pushd to docker hub. Some simplifications
are made so that app runs on kubernetes cluster. We have a helm chart for
installing all microservices. Steps to follow:

- Create a github oauth app called 'Your-Travis', and note down client id
  and secret.
- Figure out a domain for running travis.
- Generate a yaml file for travis config, say `travis.yml`:

```
travisApi:
  github:
    clientId: "your-github-oauth-app-client-id"
    clientSecret: "your-github-oauth-app-client-secret"

ingress:
  enabled: true
  annotations:
    kubernetes.io/ingress.class: traefik
  hosts:
    api: travisapi.yourdomain.com
    web: travisweb.yourdomain.com
    listener: travislistener.yourdomain.com
    build: travisbuild.yourdomain.com
    hub: travishub.yourdomain.com
    logs: travislogs.yourdomain.com

rabbitmq:
  rabbitmq:
    username: travis
    password: travis
  ingress:
    enabled: true
    hostName: travisamqp.yourdomain.com
    annotations:
      kubernetes.io/ingress.class: traefik
```

- Install helm on your local machine. For osx `brew install kubernetes-helm`
- Create a service account for tiller (server for helm), and give it tiller
  cluster admin access

~~~sh
> helm init
> kubectl create serviceaccount --namespace kube-system tiller
> kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin
    --serviceaccount=kube-system:tiller
> kubectl patch deploy --namespace kube-system tiller-deploy
    -p '{"spec":{"template":{"spec":{"serviceAccount":"tiller"}}}}'
~~~

- Add repo to pull helm chart, and install travis. Use `travis.yml` file
  generated above.

~~~sh
> helm repo add bored-im https://bored-im.github.io/travis-helm
> helm install -f travis.yml --name=travis bored-im/travis-helm
~~~

- In order to expose travis to external world, you need to install traefik
  or nginx ingress and update dns settings also.
- Go through traefik docs, and helm charts for traefik for installing it.
  Please open an issue if you are not able to do it.
- Once traefik is installed, get IP of load balancer exposed and update
  dns settings.

Thats all yo!


### TODOs

- [ ] Configure pusher so that there are realtime updates in web interface.
- [ ] Configure travis-tasks so that there are slack, github notifications.
- [ ] Teach kubernetes to travis worker so that we can scale jobs as many
      as we can.
- [ ] Improve travis-bae to work only for PRs, bake more intelligence.
- [ ] Enable travis-logs to aggregate and push to S3.
- [ ] Fix travis-hub web interface. Need to generate jwt token and stuff
- [ ] Let apps talk to each other using service name instead of actual
      web url.
- [ ] And many more to follow, which will never be done!

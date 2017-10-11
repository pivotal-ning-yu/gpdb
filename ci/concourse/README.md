## Viewing the CI

shared.ci.eng.pivotal.io/pipelines/gpdb4

Click the upper-left icon to reveal other pipelines, such as gpdb4.3.9.0

## Deploying the shared, source of truth Concourse CI pipeline for GPDB4

```
git clone git@github.com:greenplum-db/gpdb-ci-deployments.git ~/workspace/gpdb-ci-deployments
fly -t shared login -c https://shared.ci.eng.pivotal.io #use github oauth
fly -t shared sync
fly -t shared set-pipeline -p gpdb4 -c ci/concourse/pipelines/pipeline.yml -l ../gpdb-ci-deployments/gpdb-4.3_STABLE-ci-secrets.yml -l ../gpdb-ci-deployments/ccp-ci-secrets.yml
```

Over time, the thing that is most likely to change is the variables to "load vars from", the `-l` flag.

Stay tuned or ask teammates if you have questions.

## Deploying your own version of this pipeline

TBD, https://www.pivotaltracker.com/story/show/125741031

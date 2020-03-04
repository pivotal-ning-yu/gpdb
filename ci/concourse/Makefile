BRANCH ?= $(shell git rev-parse --abbrev-ref HEAD)
DEV_PIPELINE_NAME = dev-4.3-release-${BRANCH}-${USER}

.PHONY: list
list:
	@sh -c "$(MAKE) -p no_targets__ 2>/dev/null | \
	awk -F':' '/^[a-zA-Z0-9][^\$$#\/\\t=]*:([^=]|$$)/ {split(\$$1,A,/ /);for(i in A)print A[i]}' | \
	grep -v Makefile | \
	grep -v '%' | \
	grep -v '__\$$' | \
	sort"

.PHONY: set-release-prod
set-release-prod:
	fly -t prod set-pipeline \
		--check-creds \
		-p 4.3-release \
		-c pipelines/release_pipeline.yml \
		-l vars/4.3-release-pipeline.prod.yml \
		-l ~/workspace/gp-continuous-integration/secrets/gpdb-4.3-release-secrets.yml

.PHONY: set-release-dev
set-release-dev:
	fly -t dev set-pipeline \
		--check-creds \
		-p ${DEV_PIPELINE_NAME} \
		-c pipelines/release_pipeline.yml \
		-l vars/4.3-release-pipeline.dev.yml \
		-l ~/workspace/gp-continuous-integration/secrets/gpdb-4.3-release-secrets.dev.yml \
		--var=gpdb-git-branch=${BRANCH}

	fly -t dev pause-job -j ${DEV_PIPELINE_NAME}/upload_to_ms_ftp

# Copyright 2021 Hewlett Packard Enterprise Development LP

CHART_METADATA_IMAGE ?= artifactory.algol60.net/csm-docker/stable/chart-metadata
YQ_IMAGE ?= artifactory.algol60.net/docker.io/mikefarah/yq:4
HELM_IMAGE ?= artifactory.algol60.net/docker.io/alpine/helm:3.7.1
HELM_UNITTEST_IMAGE ?= artifactory.algol60.net/docker.io/quintush/helm-unittest
HELM_DOCS_IMAGE ?= artifactory.algol60.net/docker.io/jnorwood/helm-docs:v1.5.0

all: lint dep-up test package

helm:
	docker run --rm \
		--user $(shell id -u):$(shell id -g) \
		--mount type=bind,src="$(shell pwd)",dst=/src \
		-w /src \
		-e HELM_CACHE_HOME=/src/.helm/cache \
		-e HELM_CONFIG_HOME=/src/.helm/config \
		-e HELM_DATA_HOME=/src/.helm/data \
		$(HELM_IMAGE) \
		$(CMD)

lint:
	CMD="lint charts/gatekeeper"                $(MAKE) helm
	CMD="lint charts/gatekeeper-constraints"    $(MAKE) helm
	CMD="lint charts/gatekeeper-policy-library" $(MAKE) helm
	CMD="lint charts/gatekeeper-policy-manager" $(MAKE) helm

dep-up:
	CMD="dep up charts/gatekeeper"                $(MAKE) helm
	CMD="dep up charts/gatekeeper-constraints"    $(MAKE) helm
	CMD="dep up charts/gatekeeper-policy-library" $(MAKE) helm
	CMD="dep up charts/gatekeeper-policy-manager" $(MAKE) helm

test:
	docker run --rm \
		-v ${PWD}/charts:/apps \
		${HELM_UNITTEST_IMAGE} -3 \
		gatekeeper \
		gatekeeper-constraints \
		gatekeeper-policy-library \
		gatekeeper-policy-manager

package:
ifdef CHART_VERSIONS
	CMD="package charts/gatekeeper                --version $(word 1, $(CHART_VERSIONS)) -d packages" $(MAKE) helm
	CMD="package charts/gatekeeper-constraints    --version $(word 2, $(CHART_VERSIONS)) -d packages" $(MAKE) helm
	CMD="package charts/gatekeeper-policy-library --version $(word 3, $(CHART_VERSIONS)) -d packages" $(MAKE) helm
	CMD="package charts/gatekeeper-policy-manager --version $(word 3, $(CHART_VERSIONS)) -d packages" $(MAKE) helm
else
	CMD="package charts/* -d packages" $(MAKE) helm
endif

extracted-images:
	CMD="template release $(CHART) --dry-run --replace --dependency-update" $(MAKE) -s helm \
	| docker run --rm -i $(YQ_IMAGE) e -N '.. | .image? | select(.)' -

annotated-images:
	CMD="show chart $(CHART)" $(MAKE) -s helm \
	| docker run --rm -i $(YQ_IMAGE) e -N '.annotations."artifacthub.io/images"' - \
	| docker run --rm -i $(YQ_IMAGE) e -N '.. | .image? | select(.)' -

images:
	{ CHART=charts/gatekeeper                $(MAKE) -s extracted-images annotated-images; \
	  CHART=charts/gatekeeper-constraints    $(MAKE) -s extracted-images annotated-images; \
	  CHART=charts/gatekeeper-policy-library $(MAKE) -s extracted-images annotated-images; \
	  CHART=charts/gatekeeper-policy-manager $(MAKE) -s extracted-images annotated-images; \
	} | sort -u

snyk:
	$(MAKE) -s images | xargs --verbose -n 1 snyk container test

gen-docs:
	docker run --rm \
		--user $(shell id -u):$(shell id -g) \
		--mount type=bind,src="$(shell pwd)",dst=/src \
		-w /src \
		$(HELM_DOCS_IMAGE) \
		helm-docs --chart-search-root=charts

clean:
	$(RM) -r .helm packages

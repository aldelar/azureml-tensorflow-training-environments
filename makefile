# Define apps and registry
REGISTRY 		?=ailabml1b51bd50.azurecr.io
IMAGE_NAME		?=tf-2.0.0-gpu
IMAGE_VERSION	?=latest

# Docker image build and push setting
DOCKERFILE:=Dockerfile

# build
.PHONY: build
build: build-image clean-dangling

.PHONY: build-image
build-image:
	docker build -f $(DOCKERFILE) . -t $(REGISTRY)/$(IMAGE_NAME):$(IMAGE_VERSION)

# clean dangling
clean-dangling:
	$(eval DANGLING_IMAGES := $(shell docker images -f 'dangling=true' -q))
	$(if $(DANGLING_IMAGES),docker rmi --force $(DANGLING_IMAGES),)

# push
.PHONY: push
push:
	docker push $(REGISTRY)/$(IMAGE_NAME):$(IMAGE_VERSION)
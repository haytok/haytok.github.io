IMAGE_NAME=haytok.github.io
CONTAINER_NAME=haytok.github.io
PORT=1313

DOCKER_CMD := $(shell command -v docker 2>/dev/null)
FINCH_CMD  := $(shell command -v finch 2>/dev/null)
NERDCTL_CMD  := $(shell command -v nerdctl 2>/dev/null)

ifeq ($(DOCKER_CMD),)
  ifeq ($(FINCH_CMD),)
    ifeq ($(NERDCTL_CMD),)
      $(error Neither docker, finch, nor nerdctl is available in PATH)
    else
      CONTAINER_CMD := sudo nerdctl
    endif
  else
    CONTAINER_CMD := finch
  endif
else
  CONTAINER_CMD := docker
endif

$(eval USER_ID := $(shell id -u $(USER)))
$(eval GROUP_ID := $(shell id -g $(USER)))

.PHONY: build-image
build-image:
	$(CONTAINER_CMD) build -t $(IMAGE_NAME) .

.PHONY: server
server: build-image
	$(CONTAINER_CMD) run --rm -it \
		--name $(CONTAINER_NAME) \
		-v $(PWD):/project \
		-p $(PORT):1313 \
		$(IMAGE_NAME) server --bind 0.0.0.0

.PHONY: new
new: build-image
	@echo "Directory name is $(D)"

	mkdir -p content/post/$(D)

	$(CONTAINER_CMD) run --rm -it \
		-v /etc/group:/etc/group:ro \
		-v /etc/passwd:/etc/passwd:ro \
		-v $(PWD):/project \
		-u $(USER_ID):$(GROUP_ID) \
		$(IMAGE_NAME) new "content/post/$(D)/index.md"

	code "content/post/$(D)/index.md";

.PHONY: scraps
scraps: build-image
	@echo "Directory name is $(D)"

	mkdir -p content/scraps/$(D)

	$(CONTAINER_CMD) run --rm -it \
		-v /etc/group:/etc/group:ro \
		-v /etc/passwd:/etc/passwd:ro \
		-v $(PWD):/project \
		-u $(USER_ID):$(GROUP_ID) \
		$(IMAGE_NAME) new "content/scraps/$(D)/index.md"

	code "content/scraps/$(D)/index.md";

.PHONY: log
log: build-image
	@echo "Directory name is $(D)"

	mkdir -p content/log/$(D)

	$(CONTAINER_CMD) run --rm -it \
		-v /etc/group:/etc/group:ro \
		-v /etc/passwd:/etc/passwd:ro \
		-v $(PWD):/project \
		-u $(USER_ID):$(GROUP_ID) \
		$(IMAGE_NAME) new "content/log/$(D)/index.md"

	code "content/log/$(D)/index.md";

.PHONY: build
build: build-image
	$(CONTAINER_CMD) run --rm -it \
		-v /etc/group:/etc/group:ro \
		-v /etc/passwd:/etc/passwd:ro \
		-v $(PWD):/project \
		-u $(USER_ID):$(GROUP_ID) \
		$(IMAGE_NAME)

IMAGE=hugo-local
PORT=1313

DOCKER_CMD := $(shell command -v docker 2>/dev/null)
FINCH_CMD  := $(shell command -v finch 2>/dev/null)

ifeq ($(DOCKER_CMD),)
  ifeq ($(FINCH_CMD),)
    $(error Neither docker nor finch is available in PATH)
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
	$(CONTAINER_CMD) build -t $(IMAGE) .

.PHONY: server
server: build-image
	$(CONTAINER_CMD) run --rm -it \
		-v $(PWD):/project \
		-p $(PORT):1313 \
		$(IMAGE) server

.PHONY: new
new: build-image
	@echo "Directory name is $(D)"

	mkdir -p content/post/$(D)

	$(CONTAINER_CMD) run --rm -it \
		-v /etc/group:/etc/group:ro \
		-v /etc/passwd:/etc/passwd:ro \
		-v $(PWD):/project \
		-u $(USER_ID):$(GROUP_ID) \
		$(IMAGE) new "content/post/$(D)/index.md"

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
		$(IMAGE) new "content/scraps/$(D)/index.md"

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
		$(IMAGE) new "content/log/$(D)/index.md"

	code "content/log/$(D)/index.md";

.PHONY: build
build: build-image
	$(CONTAINER_CMD) run --rm -it \
		-v /etc/group:/etc/group:ro \
		-v /etc/passwd:/etc/passwd:ro \
		-v $(PWD):/project \
		-u $(USER_ID):$(GROUP_ID) \
		$(IMAGE)

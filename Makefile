VERSION=v0.148.2
IMAGE=ghcr.io/gohugoio/hugo:$(VERSION)
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

.PHONY: server
server:
	$(CONTAINER_CMD) run --rm -it \
		-v $(PWD):/project \
		-p $(PORT):1313 \
		$(IMAGE) server

.PHONY: new
new:
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
scraps:
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
log:
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
build:
	$(CONTAINER_CMD) run --rm -it \
		-v /etc/group:/etc/group:ro \
		-v /etc/passwd:/etc/passwd:ro \
		-v $(PWD):/project \
		-u $(USER_ID):$(GROUP_ID) \
		$(IMAGE)

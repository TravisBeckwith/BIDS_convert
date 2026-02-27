.PHONY: help lint test install

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

lint: ## Run ShellCheck on all shell scripts
	shellcheck -x bids_convert.sh
	shellcheck -x tests/test_bids_convert.sh

test: ## Run the test suite
	bash tests/test_bids_convert.sh

install: ## Install to /usr/local/bin (requires sudo)
	install -m 755 bids_convert.sh /usr/local/bin/bids_convert

uninstall: ## Remove from /usr/local/bin (requires sudo)
	rm -f /usr/local/bin/bids_convert

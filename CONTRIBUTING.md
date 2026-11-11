# Contributing

Keep the runtime independent of any specific game. Engine scripts may depend on
other engine scripts; game assets and behavior enter through the content provider
or explicit adapters. Keep example assets small and original, or include their
applicable license and attribution.

Run `python3 tools/check.py` before submitting a change. Add a focused regression
check for changes to interactions, state or persistence. Include a rendered
example when changing layout or input behavior.

Do not commit editor caches, exported binaries, personal saves, credentials or
local test output. Secret scanning can be run with Gitleaks:

```sh
gitleaks dir . --redact
gitleaks git . --redact --log-opts="--all"
```

## first loop

cut pasted the PRD as above.

## v2 loop

One thing, I'd rather trust rails 8 maintainer for Dockerfile and Gemfile.

1. Keep Dockerfile as installed by rails 8.
2. Add surgically to Gemfile what you need via `bundle add`

For instance, gem "google-apis-gemini_v1beta" doesnt exist, use https://github.com/gbaptista/gemini-ai instead:

```
gem 'gemini-ai', '~> 4.2.0'
```

## Loop 3 - v3

Use latest version as of today 18may2025:
* rails 8.0.2
* ruby 3.4.4
* AppName: `treasure-hunt-game/`.

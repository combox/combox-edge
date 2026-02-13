# Edge Strings

This directory stores localized string catalogs for `chat-edge`.

## Files

- `en.json`: English catalog.
- `ru.json`: Russian catalog.
- `be.json`: Belarusian catalog.
- `nl.json`: Dutch catalog.
- `uk.json`: Ukrainian catalog.
- `pl.json`: Polish catalog.
- `de.json`: German catalog.
- `ro.json`: Romanian catalog.

## Rules

- Do not hardcode user-facing text in scripts or templates.
- Add new keys to all locales in the same structure.
- Keep key names stable; update values, not keys.
- Keep catalogs valid against `strings/schema.json`.

## Locale Selection

- Locale is derived from client system/browser language via `Accept-Language`.
- Edge maps this header to supported locales and forwards `X-Client-Locale`.
- If language is not supported, fallback is `EDGE_DEFAULT_LOCALE` from `.env`.

## Key groups

- `project.*`
- `services.*`
- `routes.*`
- `status.*`
- `logs.*`
- `errors.*`

## Example lookup key

- `services.nginx`
- `errors.service_unavailable`

## Validation

- Run: `python scripts/validate_strings.py`
- Or: `make validate-strings`

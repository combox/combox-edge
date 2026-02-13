#!/usr/bin/env python3
import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
STRINGS_DIR = ROOT / "strings"
SCHEMA_PATH = STRINGS_DIR / "schema.json"
LOCALE_FILES = [
    "en.json",
    "ru.json",
    "be.json",
    "nl.json",
    "uk.json",
    "pl.json",
    "de.json",
    "ro.json",
]


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def validate_node(data, schema, path, errors):
    schema_type = schema.get("type")
    if schema_type == "object":
        if not isinstance(data, dict):
            errors.append(f"{path}: expected object, got {type(data).__name__}")
            return

        required = set(schema.get("required", []))
        props = schema.get("properties", {})
        allow_extra = schema.get("additionalProperties", True)

        missing = sorted(required - set(data.keys()))
        for key in missing:
            errors.append(f"{path}.{key}: missing required key")

        extra = sorted(set(data.keys()) - set(props.keys()))
        if not allow_extra:
            for key in extra:
                errors.append(f"{path}.{key}: unexpected key")

        for key, subschema in props.items():
            if key in data:
                validate_node(data[key], subschema, f"{path}.{key}", errors)
        return

    if schema_type == "string":
        if not isinstance(data, str):
            errors.append(f"{path}: expected string, got {type(data).__name__}")
            return
        min_len = schema.get("minLength")
        if min_len is not None and len(data) < min_len:
            errors.append(f"{path}: string length must be >= {min_len}")
        return

    errors.append(f"{path}: unsupported schema type '{schema_type}'")


def main():
    schema = load_json(SCHEMA_PATH)
    all_errors = []

    for locale in LOCALE_FILES:
        file_path = STRINGS_DIR / locale
        if not file_path.exists():
            all_errors.append(f"{locale}: file not found")
            continue

        try:
            data = load_json(file_path)
        except json.JSONDecodeError as exc:
            all_errors.append(f"{locale}: invalid JSON ({exc})")
            continue

        locale_errors = []
        validate_node(data, schema, locale, locale_errors)
        all_errors.extend(locale_errors)

    if all_errors:
        print("String validation failed:")
        for err in all_errors:
            print(f"- {err}")
        return 1

    print("String validation passed for all locales.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

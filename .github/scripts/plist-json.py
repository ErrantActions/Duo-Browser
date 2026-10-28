"""Convert trusted-job temporary plist metadata without printing its contents."""

import base64
import datetime
import json
import plistlib
import sys
from pathlib import Path


def normalize(value: object) -> object:
    if isinstance(value, bytes):
        return base64.b64encode(value).decode("ascii")
    if isinstance(value, datetime.datetime):
        if value.tzinfo is None:
            value = value.replace(tzinfo=datetime.timezone.utc)
        return value.astimezone(datetime.timezone.utc).isoformat()
    if isinstance(value, dict):
        return {key: normalize(child) for key, child in value.items()}
    if isinstance(value, list):
        return [normalize(child) for child in value]
    return value


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("Supply input plist and private output JSON paths.")
    try:
        value = plistlib.loads(Path(sys.argv[1]).read_bytes())
        if not isinstance(value, dict):
            raise ValueError("Expected a property-list dictionary.")
        Path(sys.argv[2]).write_text(
            json.dumps(normalize(value), allow_nan=False), encoding="utf-8"
        )
    except (OSError, ValueError, TypeError, plistlib.InvalidFileException):
        raise SystemExit("Signing property-list metadata could not be decoded.") from None


if __name__ == "__main__":
    main()

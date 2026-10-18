#!/usr/bin/env python3
"""Sync the static icon, and optionally its rendered background, into Sketch."""

import argparse
import copy
import hashlib
import io
import json
import os
from pathlib import Path
import re
import stat
import struct
import tempfile
import zipfile
import zlib


SKETCH = (
    Path(__file__).resolve().parent.parent
    / "assets/dmg-background/Neovide Liquid Glass Installer.sketch"
)
ICON_IDS = {
    "4008DED7-D3A6-4351-8756-7980472A0A9A",
    "25A2BE9B-E093-41DE-B404-D4C3F255D8C6",
}
BACKGROUND_ID = "B659F24F-7121-4C7E-82B7-912D8BC75C5F"


def read_png(path, expected_size):
    data = path.read_bytes()
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError(f"Not a PNG: {path}")
    position = 8
    chunks = []
    while position < len(data):
        if position + 12 > len(data):
            raise ValueError(f"Truncated PNG: {path}")
        size = struct.unpack_from(">I", data, position)[0]
        end = position + size + 12
        if end > len(data):
            raise ValueError(f"Truncated PNG chunk: {path}")
        kind = data[position + 4 : position + 8]
        payload = data[position + 8 : end - 4]
        checksum = struct.unpack_from(">I", data, end - 4)[0]
        if zlib.crc32(kind + payload) & 0xFFFFFFFF != checksum:
            raise ValueError(f"Invalid PNG checksum: {path}")
        chunks.append((kind, payload))
        position = end
        if kind == b"IEND":
            break
    if (
        not chunks
        or chunks[0][0] != b"IHDR"
        or len(chunks[0][1]) != 13
        or chunks[-1] != (b"IEND", b"")
        or position != len(data)
        or not any(kind == b"IDAT" for kind, _ in chunks)
    ):
        raise ValueError(f"Incomplete PNG: {path}")
    dimensions = struct.unpack_from(">II", chunks[0][1])
    if dimensions != expected_size:
        raise ValueError(
            f"Expected {expected_size[0]} × {expected_size[1]} PNG, "
            f"got {dimensions[0]} × {dimensions[1]}: {path}"
        )
    return data


def objects(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from objects(child)
    elif isinstance(value, list):
        for child in value:
            yield from objects(child)


def checked_archive(data):
    archive = zipfile.ZipFile(io.BytesIO(data))
    names = archive.namelist()
    if len(names) != len(set(names)):
        archive.close()
        raise ValueError("Sketch archive contains duplicate ZIP entries")
    for name in ("document.json", "meta.json"):
        if name not in names:
            archive.close()
            raise ValueError(f"Sketch archive is missing {name}")
    failed = archive.testzip()
    if failed is not None:
        archive.close()
        raise ValueError(f"Sketch ZIP checksum failed: {failed}")
    return archive


def update(icon, background):
    replacements = [(ICON_IDS, read_png(icon, (1024, 1024)))]
    if background is not None:
        replacements.append(({BACKGROUND_ID}, read_png(background, (1300, 900))))

    initial_stat = SKETCH.stat()
    original = SKETCH.read_bytes()
    temporary_path = None
    with checked_archive(original) as archive:
        infos = archive.infolist()
        contents = {info.filename: archive.read(info) for info in infos}
        documents = {
            name: json.loads(data)
            for name, data in contents.items()
            if name.endswith(".json")
        }
        bitmap_objects = {}
        reference_counts = {}
        for document in documents.values():
            for item in objects(document):
                reference = item.get("_ref")
                if isinstance(reference, str):
                    reference_counts[reference] = reference_counts.get(reference, 0) + 1
                if item.get("_class") == "bitmap":
                    bitmap_objects.setdefault(item.get("do_objectID"), []).append(item)

        reference_changes = {}
        new_images = {}
        image_templates = {}
        for target_ids, image in replacements:
            new_reference = f"images/{hashlib.sha1(image).hexdigest()}.png"
            old_references = {}
            for target_id in target_ids:
                matches = bitmap_objects.get(target_id, [])
                if len(matches) != 1:
                    raise ValueError(f"Expected exactly one bitmap with ID {target_id}")
                old_reference = matches[0].get("image", {}).get("_ref")
                if not isinstance(old_reference, str) or old_reference not in contents:
                    raise ValueError(f"Missing bitmap image for {target_id}")
                old_references[old_reference] = old_references.get(old_reference, 0) + 1
            for old_reference, count in old_references.items():
                # Replacing only complete _ref values preserves all unrelated JSON bytes.
                if reference_counts.get(old_reference) != count:
                    raise ValueError(f"Image is also referenced by another layer: {old_reference}")
                existing = reference_changes.get(old_reference)
                if existing is not None and existing != new_reference:
                    raise ValueError(f"Conflicting image updates: {old_reference}")
                reference_changes[old_reference] = new_reference
                image_templates.setdefault(new_reference, archive.getinfo(old_reference))
            if new_reference in contents and contents[new_reference] != image:
                raise ValueError(f"Image hash collision in Sketch: {new_reference}")
            new_images[new_reference] = image

        changed_json = {}
        for name in documents:
            source = contents[name].decode("utf-8")
            for old_reference, new_reference in reference_changes.items():
                if old_reference != new_reference:
                    source = re.sub(
                        r'("_ref"\s*:\s*)' + re.escape(json.dumps(old_reference)),
                        lambda match: match[1] + json.dumps(new_reference),
                        source,
                    )
            encoded = source.encode("utf-8")
            if encoded != contents[name]:
                changed_json[name] = encoded

        removed = {
            old_reference
            for old_reference, new_reference in reference_changes.items()
            if old_reference != new_reference and old_reference not in new_images
        }
        if not changed_json and all(contents.get(name) == data for name, data in new_images.items()):
            print("Sketch already contains the supplied images.")
            return

        try:
            descriptor, temporary_name = tempfile.mkstemp(
                prefix=f".{SKETCH.name}.", suffix=".tmp", dir=SKETCH.parent
            )
            temporary_path = Path(temporary_name)
            os.close(descriptor)
            with zipfile.ZipFile(temporary_path, "w") as output:
                output.comment = archive.comment
                written = set()
                for info in infos:
                    name = info.filename
                    if name in removed:
                        continue
                    output.writestr(copy.copy(info), changed_json.get(name, new_images.get(name, contents[name])))
                    written.add(name)
                for name, image in new_images.items():
                    if name not in written:
                        info = copy.copy(image_templates[name])
                        info.filename = name
                        info.orig_filename = name
                        output.writestr(info, image)

            with checked_archive(temporary_path.read_bytes()) as result:
                for name, image in new_images.items():
                    if result.read(name) != image:
                        raise ValueError(f"Written image differs from the source: {name}")
                for name, data in changed_json.items():
                    json.loads(data)
                    if result.read(name) != data:
                        raise ValueError(f"Written Sketch page differs from the update: {name}")
            current_stat = SKETCH.stat()
            if (
                current_stat.st_ino,
                current_stat.st_size,
                current_stat.st_mtime_ns,
            ) != (
                initial_stat.st_ino,
                initial_stat.st_size,
                initial_stat.st_mtime_ns,
            ):
                raise ValueError("Sketch changed while updating; the source was left untouched")
            os.chmod(temporary_path, stat.S_IMODE(initial_stat.st_mode))
            with temporary_path.open("rb") as pending:
                os.fsync(pending.fileno())
            os.replace(temporary_path, SKETCH)
            temporary_path = None
        finally:
            if temporary_path is not None:
                temporary_path.unlink(missing_ok=True)
    print(f"Updated {len(ICON_IDS)} icon layers" + (" and the background cache." if background else "."))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("icon_png", type=Path, help="The exported 1024 × 1024 static icon")
    parser.add_argument(
        "background_png", nargs="?", type=Path, help="Optional rendered 1300 × 900 installer background"
    )
    args = parser.parse_args()
    try:
        update(args.icon_png, args.background_png)
    except (OSError, ValueError, KeyError, zipfile.BadZipFile) as error:
        parser.exit(1, f"Cannot update installer source: {error}\n")


if __name__ == "__main__":
    main()

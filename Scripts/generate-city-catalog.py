#!/usr/bin/env python3
"""Build the offline catalog from GeoNames CC BY 4.0 export files.

Usage: python3 Scripts/generate-city-catalog.py cities15000.zip admin1CodesASCII.txt countryInfo.txt
Download inputs from https://download.geonames.org/export/dump/.
The app never downloads city data at runtime. This script uses only Python's standard library.
"""

import hashlib
import pathlib
import sys
import unicodedata
import zipfile


def normalized(text):
    text = "".join(c for c in unicodedata.normalize("NFKD", text).lower() if not unicodedata.combining(c))
    return " ".join("".join(c if c.isalnum() else " " for c in text).split())


def lines(path):
    return (line.rstrip("\n").split("\t") for line in pathlib.Path(path).read_text().splitlines() if line and not line.startswith("#"))


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    archive, admin_path, country_path = map(pathlib.Path, sys.argv[1:])
    regions = {fields[0]: fields[1] for fields in lines(admin_path)}
    countries = {fields[0]: fields[4] for fields in lines(country_path)}
    # Keep familiar English menu names while retaining all source names as search aliases.
    names = {5128581: "New York", 1526273: "Astana"}
    extra_aliases = {1526273: ["Nur-Sultan", "Nur Sultan"], 5128581: ["NYC"]}
    country_aliases = {"GB": "UK", "US": "USA United States of America"}
    rows = []
    with zipfile.ZipFile(archive) as source:
        for line in source.read("cities15000.txt").decode("utf-8").splitlines():
            fields = line.split("\t")
            geoid, source_name, ascii_name, aliases = fields[:4]
            geoid = int(geoid)
            country, admin, population, zone = fields[8], fields[10], int(fields[14]), fields[17]
            if not zone or not country:
                continue
            if geoid == 1526273:
                zone = "Asia/Almaty"  # Astana uses UTC+5 after Kazakhstan's March 2024 change.
            name = names.get(geoid, source_name)
            region = regions.get(f"{country}.{admin}", "")
            full = ", ".join(dict.fromkeys(value for value in [name, region, country] if value))
            alias_set = sorted({normalized(value) for value in [source_name, ascii_name, *aliases.split(","), *extra_aliases.get(geoid, [])] if value})
            searchable = normalized(" ".join([name, full, countries.get(country, ""), country_aliases.get(country, ""), admin, zone]))
            rows.append((population, geoid, [str(geoid), name, full, zone, str(population), "|".join(alias_set), searchable]))
    rows.sort(key=lambda row: (-row[0], row[1]))
    root = pathlib.Path(__file__).resolve().parents[1]
    output = root / "Sources/ClockTowerCore/Resources"
    output.mkdir(parents=True, exist_ok=True)
    data = "".join("\t".join(row[2]) + "\n" for row in rows)
    (output / "cities.tsv").write_text(data, encoding="utf-8")
    metadata = "\n".join(f"{name}: {hashlib.sha256(path.read_bytes()).hexdigest()}" for name, path in zip(
        ["cities15000.zip", "admin1CodesASCII.txt", "countryInfo.txt"], [archive, admin_path, country_path]))
    (output / "catalog-source.txt").write_text(f"GeoNames cities15000, {len(rows):,} cities.\nInput SHA-256 digests:\n{metadata}\n", encoding="utf-8")
    print(f"Wrote {len(rows):,} cities ({len(data.encode('utf-8')):,} bytes).")


if __name__ == "__main__":
    main()

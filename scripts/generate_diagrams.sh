# ========================================================================
# SOVEREIGN LEVIATHAN NODE LICENSE
# License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
# Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
# ========================================================================
#
# This file is a covered work under the GNU Affero General Public License,
# version 3, together with the Sovereign Leviathan additional terms.
#
# Hark, though this node be but a spark,
# Its covenant endureth through the dark.
#
# Ignorantia juris non excusat.
# ========================================================================

#!/usr/bin/env bash
# tools/generate_diagrams_and_insert.sh
# Usage: ./generate_diagrams_and_insert.sh
# Produces SVG and PNG from DOT files and inserts image links into README.md
set -euo pipefail

DIAGRAM_DIR="diagrams"
OUT_DIR="docs/images"
README="docs/README.md"

mkdir -p "$DIAGRAM_DIR" "$OUT_DIR"

if ! command -v dot >/dev/null 2>&1; then
  echo "Error: Graphviz 'dot' not found. Install: sudo apt-get install graphviz" >&2
  exit 1
fi

render_dot() {
  local dotfile="$1"
  local svg_out="$2"
  local png_out="$3"
  echo "Rendering $dotfile -> $svg_out"
  dot -Tsvg "$dotfile" -o "$svg_out"
  if command -v rsvg-convert >/dev/null 2>&1; then
    rsvg-convert -w 1600 -h 800 "$svg_out" -o "$png_out"
  elif command -v convert >/dev/null 2>&1; then
    convert "$svg_out" -resize 1600x800 "$png_out"
  else
    echo "Warning: neither rsvg-convert nor convert found; PNG not generated."
  fi
}

for dotfile in "$DIAGRAM_DIR"/*.dot; do
  base="$(basename "$dotfile" .dot)"
  render_dot "$dotfile" "$OUT_DIR/${base}.svg" "$OUT_DIR/${base}.png"
done

insert_image() {
  local placeholder="$1"
  local img_rel="$2"
  local alt="$3"
  awk -v ph="$placeholder" -v img="$img_rel" -v alt="$alt" '
    BEGIN{replaced=0}
    {
      if($0 ~ ph && replaced==0){
        print "![" alt "](" img ")"
        replaced=1
      } else {
        print $0
      }
    }
  ' "$README" > "$README.tmp" && mv "$README.tmp" "$README"
}

if [ -f "$README" ]; then
  insert_image "<!-- FLOWCHART_IMAGE -->" "images/pipeline_flowchart.svg" "Pipeline flowchart"
  insert_image "<!-- ARCH_IMAGE -->"       "images/architecture.svg"       "Architecture diagram"
  insert_image "<!-- INST_IMAGE -->"       "images/institutional_architecture.svg" "Institutional architecture"
  insert_image "<!-- SQL_IMAGE -->"        "images/sql_schema.svg"         "SQL schema"
  insert_image "<!-- SAS_IMAGE -->"        "images/sas_dataflow.svg"       "SAS data flow"
  echo "README updated."
fi

echo "Done. Images written to $OUT_DIR"

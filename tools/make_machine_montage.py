#!/usr/bin/env python3
from pathlib import Path
import sys

from PIL import Image, ImageDraw, ImageFont


def main() -> None:
    output = Path(sys.argv[1])
    kinds = [
        "miner_mk1", "smelter", "constructor", "assembler", "geo_tap",
        "power_pole", "storage", "splitter", "merger", "belt",
        "spire", "hub", "drop_pod",
    ]
    cell_width, image_height, label_height = 400, 225, 34
    columns = 4
    rows = (len(kinds) + columns - 1) // columns
    montage = Image.new("RGB", (columns * cell_width, rows * (image_height + label_height)), "#20262a")
    draw = ImageDraw.Draw(montage)
    font = ImageFont.load_default()
    for index, kind in enumerate(kinds):
        path = output / f"{kind}.png"
        if not path.exists():
            raise SystemExit(f"Missing machine capture: {path}")
        image = Image.open(path).convert("RGB")
        image.thumbnail((cell_width, image_height), Image.Resampling.LANCZOS)
        x = (index % columns) * cell_width
        y = (index // columns) * (image_height + label_height)
        montage.paste(image, (x + (cell_width - image.width) // 2, y))
        draw.text((x + 10, y + image_height + 8), kind.replace("_", " ").title(), fill="white", font=font)
    montage.save(output / "machine-montage.png", quality=92)


if __name__ == "__main__":
    main()

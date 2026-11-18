---
name: fantasi
description: Make images on this machine with a local model through Fantasi's command line. Use when a task needs an image made rather than found, such as a website's hero image, a placeholder illustration, a game sprite, an app icon idea or a desktop background, and the user hasn't asked for a cloud service.
---

# Fantasi

`fantasi generate` makes one image with the local image model Omarchy runs, saves it as a PNG, and prints where.

```sh
fantasi generate "a calm mountain lake at dusk, navy and teal, mist over the water"
fantasi generate "flat app icon of a paper boat on a teal circle" --width 1024 --height 1024 --json
```

- It prints the path on success (`{"path": "…"}` with `--json`) and exits 0; on failure it says why on stderr after `Error:` and exits 1.
- Images go to `~/Pictures/Generated`, named by time and the prompt's first words. Copy the file where the project needs it; don't move it, since the user browses that folder in Fantasi.
- An image takes about half a minute. Make them one at a time; the model runs one job at once.
- To change an image rather than make a new one, start from it: `fantasi generate "the same lighthouse, with snow on the rocks" --from ~/Pictures/Generated/….png`. `--from` takes any picture, a photo too: it is scaled and cut from the middle to the nearest size near a megapixel in its own shape. Describe the whole picture you want, not only the change; the new image keeps the base's composition.
- Options: `--width` and `--height` in pixels (multiples of 64 up to about a megapixel work best: 1024×1024, 1344×768, 768×1344), `--steps` (the model's own default when left out), `--seed` for a repeatable image.
- Write the prompt as a description of the picture: subject, setting, light, colors, composition. Say "no text" when the image must not contain lettering.

When it says no image model is running, tell the user and show the command it suggests (`omarchy agent local start …` or `omarchy agent local use …`). Don't start or install one yourself: it can stop a text model the user is relying on.

The images belong to the user. Mention the path of every image you make.

# Fantasi

Make images on your own machine with Omarchy's local image models.

![Fantasi showing a lighthouse with a red cabin beside it, the actions under it and earlier images in the history](docs/screenshot.png)

Describe an image and watch it sharpen. Then change it by saying what should change, start from a picture of your own, or combine up to four. With a video model running, animate a picture into a short clip with sound, or make one from a prompt. Everything is kept in `~/Pictures/Generated` with its prompt.

Fantasi uses the image model [omarchy-local-ai](https://github.com/omacom/omarchy-local-ai) runs, and offers to start or set one up when none is running.

## Shortcuts

| Keys | Action |
| --- | --- |
| Enter | Make the image |
| Esc | Stop, or go back |
| Ctrl+E | Change it |
| Ctrl+N | New image |
| Ctrl+M | Animate it |
| Ctrl+O | Add a picture |
| Ctrl+1, 2, 3 | Screen, square or portrait |
| Ctrl+B | Show or hide the history |
| F1 | All shortcuts |

## Command line

```sh
fantasi generate "a calm lake at dusk"
fantasi generate "make it night" --from lake.png
fantasi generate --video "the mist lifts off the lake" --from lake.png
fantasi skill install    # teach your coding agents to make images
```

## License

MIT.

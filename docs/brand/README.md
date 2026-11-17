# Brand artwork

The Pindu OS icon and the images made from it. The icon is the source of everything else here, together with one
screenshot of Pindu launcher's fullscreen Home for the television on the banner.

| File | Size | Use |
| --- | --- | --- |
| [`icon.png`](icon.png) | 1024x1024, transparent | The icon on its rounded square. Scale it down for smaller sizes. |
| [`readme-banner.webp`](readme-banner.webp) | 2560x800, shown at 1280x400, transparent corners | The top of the [README](../../README.md) |
| [`social-preview.png`](social-preview.png) | 1280x640 | The repository's social preview: **Settings → General → Social preview** |
| [`source/fullscreen-home.webp`](source/fullscreen-home.webp) | 1920x1080 | The screenshot on the television, copied from [`pindu-launcher`](https://github.com/Tim-van-Oudheusden/pindu-launcher/blob/main/docs/screenshots/fullscreen-1-home.webp) |
| [`lockup-for-dark.png`](lockup-for-dark.png) | 900x320, transparent | Icon and name, for dark pages |
| [`lockup-for-light.png`](lockup-for-light.png) | 900x320, transparent | Icon and name, for light pages |

GitHub has no API for the social preview, so a person uploads `social-preview.png` once, and again when it changes.

## Rendering the images

Everything except the icon is drawn by [`source/scene.html`](source/scene.html), a page with one layout per image, and
rendered by [`source/build.js`](source/build.js) with headless Chromium. It needs Node.js with
[Playwright](https://playwright.dev) and the [Inter](https://github.com/rsms/inter) typeface (Inter and Inter Display)
installed.

```sh
cd docs/brand/source
node build.js                       # the files in docs/brand/
node build.js --extras ~/pindu-art  # article covers, a link-preview image and an avatar, into a folder of your own
```

- **The words.** The tagline and the line under it are the `SUB` and `LINE` constants at the top of `build.js`.
- **The layouts.** Each image picks a layout by class name (`banner`, `social`, `cover`, `avatar`, `lockup`); the
  sizes and positions are at the end of the style sheet in `scene.html`. `light` gives a layout the light background
  the banner and the social preview use, and `tv: 1` adds the television.
- **The screenshot.** To show another screen on the television, replace `source/fullscreen-home.webp` with a
  1920x1080 image. The game art in it belongs to each game's publisher.
- **The colours.** Navy `#00021a`, deep blue `#0a1c66`, blue `#0a6cf0`, cyan `#49f0fd` and sky `#82bffc`, taken from
  the icon. The light background runs from `#f6fbff` to `#c4dfff`.

The extras are not kept in the repository: they are for articles and profiles, and the command above makes them when
they are needed.

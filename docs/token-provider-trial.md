# Token provider trial

On 3 November 2026, `yt-dlp` with [bgutil's PO token provider](https://github.com/Brainicism/bgutil-ytdlp-pot-provider) downloaded `zGv68RvajSY` successfully from the development Mac's normal connection, without account cookies or a proxy.

Versions: `yt-dlp` 2026.10.26, `yt-dlp-ejs` 0.8.0, bgutil provider/plugin 2.0.2, Node 25.6.1. Provider source: `26475e9d3665b972c4aeb83b4dbaafcf64b88438`.

The plugin requested a GVS token for the `mweb` client and the provider generated it. The completed MP4 contained 1920×1080 H.264 video and English stereo AAC audio, with a duration of 1894.586 seconds and a size of 714,185,548 bytes. A three-second sample at 15 minutes decoded successfully.

This establishes that the combination worked once from this connection. There was no simultaneous control attempt without a token, so it does not establish that the token alone resolved the earlier block. It has not been integrated into the iOS app or tested from Cloudflare. The existing Worker still uses YouTubeKit-Server's extraction path.

## Reproduce locally

Requires Git, `uv`, Node 22 or later, npm and FFmpeg. Use a separate working directory outside this repository:

```sh
git clone --branch 2.0.2 --depth 1 https://github.com/Brainicism/bgutil-ytdlp-pot-provider.git
uv venv .venv
uv pip install --python .venv/bin/python 'yt-dlp[default]==2026.10.26' 'yt-dlp-ejs==0.8.0' 'bgutil-ytdlp-pot-provider==2.0.2'
cd bgutil-ytdlp-pot-provider/server
npm ci
npx tsc
node build/main.js --host 127.0.0.1 --port 4417
```

Keep that terminal running. In another terminal, from the directory containing `.venv`, run one download:

```sh
.venv/bin/python -m yt_dlp \
  --ignore-config --no-playlist --no-cache-dir --proxy '' \
  --js-runtimes node --sleep-requests 2 \
  --retries 0 --fragment-retries 0 --extractor-retries 0 --socket-timeout 30 \
  --extractor-args 'youtube:player_client=mweb' \
  --extractor-args 'youtubepot-bgutilhttp:base_url=http://127.0.0.1:4417' \
  --format 'bv[height<=1080][vcodec^=avc1]+ba[ext=m4a]/b[height<=1080][ext=mp4]' \
  --merge-output-format mp4 --output '%(id)s.%(ext)s' \
  'https://www.youtube.com/watch?v=zGv68RvajSY'
```

Stop the provider with Ctrl-C afterwards. Its logs can contain generated tokens; keep them local and out of Git. The upstream provider documentation explains that token generation does not guarantee avoiding bot checks or IP-based login restrictions.

## Backend implications

The provider exposes a local token-generation service for yt-dlp; installing it does not add token support to YouTubeKit. A backend integration needs to run the extractor and token provider together, and keep extraction and media transfers on a compatible network/session. Validate that deployment before switching the app's endpoint. No Google account cookies were read or uploaded during this trial.

# PR #2 reconciliation validation

The reconciliation includes main commit 71490795a36217b7868b61f320298a24f9570a30,
including the one-time 12-second HD resolution retry after SD fails and HD was
not previously available. Approved parent origins and both overlay fixes remain.
Default-branch monitoring changes are retained without dispatching monitoring jobs.

Integration corrections:
- Invalidate failed HLS generations, clear readiness, and detach failed playback
  before the longer HD lookup; ignore old HLS events and old play promises.
- Manual retry tears down old playback before resolving a fresh HD URL.
- Only actual HLS playing events count as playback; loadeddata alone is insufficient.
- Ignore YouTube callbacks and delayed autoplay tasks from obsolete players.
- Destroy YouTube playback on terminal error so old events cannot hide the overlay.
- Reset the YouTube recovery budget only on observed non-buffering time progress,
  rather than merely elapsed wall time while paused/hidden/buffering.

## Automated checks

Run `node --test tests/players.test.cjs` (Node 18+; no dependencies).
The VM harness executes the actual inline scripts with mocked DOM/media, network,
and YouTube objects. It checks origin targets, URL rejection, delayed HD recovery,
retry races, bounded YouTube recovery, pause/background behavior, and overlay CSS.
It is not real-browser playback or computed-layout verification.
Also run `git diff --check`, compile all inline player scripts with `vm.Script`,
and `sh -n` on both maintenance scripts. Do not run uptime scripts as tests:
they probe production and dispatch successor workflows.

## Required before merge / Pages publication

Use the exact PR candidate served from a local or isolated test origin, without
changing production Pages. Test both quran and sunnah on Chrome/Firefox (hls.js),
Safari/iOS (native HLS), and the application's Android/iOS WebViews.

- Real HD startup and sound/muted autoplay; unmute works. loadeddata without
  playback must not report playing or suppress the startup guard.
- Force first HD lookup to exceed 6 seconds and SD manifests to return 404;
  second lookup succeeds within 12 seconds and starts HD. If it also fails,
  exactly one retry is made and the error overlay/retry button is usable.
- HD starts then fails: SD fallback, finite fatal-error recovery, freeze handling.
- Rapid manual retries while HD resolution/play promises are pending; no stale
  callback may replace playback or hide an error. Check native HLS teardown.
- Receive status in each approved HTTPS parent; verify an unrelated parent gets
  no messages. Verify ReactNativeWebView receives the unchanged payload format.
- YouTube actual live time progression, PLAYING freeze (two unchanged samples),
  BUFFERING freeze (four), three rebuilds then a usable error overlay; retries,
  hide/resume, intentional pause, and 60 seconds of advancing playback.
- YouTube 101/150/153 fallback to nocookie remains available after freeze recovery;
  old callbacks cannot affect replacements; test blocked autoplay after buffering.
- Computed overlay stacking and click hit-testing over video, iframe, and controls.

No live browser playback has been validated in this execution. Automated checks
must not be treated as approval to merge; merging publishes the players immediately.

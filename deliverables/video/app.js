(function () {
  "use strict";

  var scenes = Array.prototype.slice.call(document.querySelectorAll(".scene"));
  var durations = scenes.map(function (scene) { return Number(scene.dataset.duration) || 1; });
  var starts = [];
  var total = durations.reduce(function (sum, duration) { starts.push(sum); return sum + duration; }, 0);
  var state = { time: 0, playing: false, index: 0, frame: null, startedAt: 0, lastIndex: -1 };
  var params = new URLSearchParams(location.search);

  var playButton = document.getElementById("play");
  var playIcon = document.getElementById("play-icon");
  var timeline = document.getElementById("timeline");
  var progress = document.getElementById("progress");
  var scrubber = document.getElementById("scrubber");
  var timeLabel = document.getElementById("time-label");
  var sceneTitle = document.getElementById("scene-title");
  var player = document.getElementById("player");

  function pad(value) { return String(value).padStart(2, "0"); }
  function timecode(seconds) {
    seconds = Math.max(0, Math.floor(seconds));
    return pad(Math.floor(seconds / 60)) + ":" + pad(seconds % 60);
  }

  function indexAt(time) {
    if (time >= total) return scenes.length - 1;
    for (var index = scenes.length - 1; index >= 0; index -= 1) {
      if (time >= starts[index]) return index;
    }
    return 0;
  }

  function animateCounter(scene) {
    var counter = scene.querySelector(".count-up");
    if (!counter) return;
    var target = Number(counter.dataset.value);
    if (!Number.isFinite(target)) return;
    var started = performance.now();
    var duration = 1100;
    function update(now) {
      var ratio = Math.min(1, (now - started) / duration);
      var eased = 1 - Math.pow(1 - ratio, 3);
      counter.textContent = Math.round(target * eased).toLocaleString("en-US");
      if (ratio < 1 && scene.classList.contains("active")) requestAnimationFrame(update);
    }
    requestAnimationFrame(update);
  }

  function activate(index) {
    index = Math.max(0, Math.min(scenes.length - 1, index));
    if (state.lastIndex === index) return;
    scenes.forEach(function (scene, sceneIndex) {
      scene.classList.toggle("active", sceneIndex === index);
      scene.setAttribute("aria-hidden", sceneIndex === index ? "false" : "true");
    });
    state.index = index;
    state.lastIndex = index;
    sceneTitle.textContent = scenes[index].dataset.title || "島語通正式版動畫";
    animateCounter(scenes[index]);
    document.title = "島語通｜" + (scenes[index].dataset.title || "正式版動畫");
  }

  function render() {
    state.time = Math.max(0, Math.min(total, state.time));
    activate(indexAt(state.time));
    var ratio = total ? state.time / total : 0;
    progress.style.width = (ratio * 100) + "%";
    scrubber.style.left = (ratio * 100) + "%";
    timeline.setAttribute("aria-valuenow", String(Math.round(state.time)));
    timeLabel.textContent = timecode(state.time) + " / " + timecode(total);
    playIcon.textContent = state.playing ? "Ⅱ" : "▶";
    playButton.setAttribute("aria-label", state.playing ? "暫停" : "播放");
  }

  function tick(now) {
    if (!state.playing) return;
    state.time = (now - state.startedAt) / 1000;
    if (state.time >= total) {
      state.time = total;
      state.playing = false;
      render();
      return;
    }
    render();
    state.frame = requestAnimationFrame(tick);
  }

  function play() {
    if (state.time >= total) state.time = 0;
    state.playing = true;
    state.startedAt = performance.now() - state.time * 1000;
    cancelAnimationFrame(state.frame);
    state.frame = requestAnimationFrame(tick);
    render();
  }

  function pause() {
    if (state.playing) state.time = (performance.now() - state.startedAt) / 1000;
    state.playing = false;
    cancelAnimationFrame(state.frame);
    render();
  }

  function togglePlay() { state.playing ? pause() : play(); }

  function seek(time, keepPlaying) {
    state.time = Math.max(0, Math.min(total, time));
    state.lastIndex = -1;
    if (state.playing || keepPlaying) {
      state.playing = true;
      state.startedAt = performance.now() - state.time * 1000;
      cancelAnimationFrame(state.frame);
      state.frame = requestAnimationFrame(tick);
    }
    render();
  }

  function goScene(index) { seek(starts[Math.max(0, Math.min(scenes.length - 1, index))], state.playing); }

  function seekFromPointer(event) {
    var rect = timeline.getBoundingClientRect();
    var ratio = Math.max(0, Math.min(1, (event.clientX - rect.left) / rect.width));
    seek(ratio * total, state.playing);
  }

  playButton.addEventListener("click", togglePlay);
  document.getElementById("prev").addEventListener("click", function () { goScene(state.index - 1); });
  document.getElementById("next").addEventListener("click", function () { goScene(state.index + 1); });
  document.getElementById("fullscreen").addEventListener("click", function () {
    if (document.fullscreenElement) document.exitFullscreen();
    else document.documentElement.requestFullscreen().catch(function () {});
  });
  timeline.addEventListener("click", seekFromPointer);
  timeline.addEventListener("keydown", function (event) {
    if (event.key === "ArrowRight") { event.preventDefault(); seek(state.time + 5, state.playing); }
    if (event.key === "ArrowLeft") { event.preventDefault(); seek(state.time - 5, state.playing); }
    if (event.key === "Home") { event.preventDefault(); seek(0, state.playing); }
    if (event.key === "End") { event.preventDefault(); seek(total, state.playing); }
  });

  document.addEventListener("keydown", function (event) {
    if (event.target && /INPUT|TEXTAREA|BUTTON/.test(event.target.tagName)) return;
    if (event.code === "Space") { event.preventDefault(); togglePlay(); }
    else if (event.key === "ArrowRight") goScene(state.index + 1);
    else if (event.key === "ArrowLeft") goScene(state.index - 1);
    else if (event.key.toLowerCase() === "f") document.getElementById("fullscreen").click();
    else if (event.key.toLowerCase() === "r") seek(0, false);
  });

  var requestedScene = Number(params.get("scene"));
  if (Number.isFinite(requestedScene) && requestedScene >= 1 && requestedScene <= scenes.length) state.time = starts[requestedScene - 1];
  if (params.get("controls") === "0") player.classList.add("hidden");
  if (params.get("record") === "1") {
    document.body.classList.add("recording");
    document.getElementById("record-badge").hidden = false;
  }
  render();
  if (params.get("autoplay") === "1" || params.get("record") === "1") window.setTimeout(play, 700);
}());

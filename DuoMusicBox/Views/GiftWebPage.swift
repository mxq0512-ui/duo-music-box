import Foundation
import UniformTypeIdentifiers

/// 网页礼物：把一份礼物打包成单个 HTML 文件——旋律数据以 JSON 内嵌，
/// 播放器用 WebAudio 按与 App 完全相同的音色配方合成（泛音比/幅度/衰减
/// 与 MusicBoxAudioEngine.synthesizeTone 一致，步长 = 60/BPM/2）。
/// 收到的人在浏览器或微信里打开文件、点播放就能听，不需要安装 App。
/// 用户文字（标题/祝福语）只经 JSON 进入页面并以 textContent 呈现，不拼 HTML。
public enum GiftWebPage {

    /// 页面模板（占位符 /*__GIFT__*/null 在生成时被礼物 JSON 取代）。
    private static let template = #"""
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>八音盒礼物</title>
<style>
  :root { color-scheme: dark; }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    min-height: 100vh;
    background: radial-gradient(120% 90% at 50% 0%, #3a2415 0%, #241610 55%, #150d08 100%);
    color: #f3e5c0;
    font-family: -apple-system, "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", sans-serif;
    display: flex; align-items: center; justify-content: center;
    padding: 22px 14px 30px;
  }
  .card {
    width: 100%; max-width: 520px;
    background: linear-gradient(180deg, rgba(255,214,120,.06), rgba(0,0,0,.18));
    border: 1px solid rgba(212,175,55,.45);
    border-radius: 18px;
    padding: 26px 20px 22px;
    box-shadow: 0 18px 50px rgba(0,0,0,.55), inset 0 1px 0 rgba(255,220,140,.15);
    text-align: center;
  }
  .brand { font-size: 11px; letter-spacing: .42em; color: #c9a227; text-transform: uppercase; }
  .brand::before, .brand::after { content: "✦"; letter-spacing: 0; margin: 0 10px; color: rgba(212,175,55,.6); }
  h1 {
    font-family: "Songti SC", "Noto Serif SC", serif;
    font-size: 27px; font-weight: 600; margin: 14px 0 4px; color: #f7ead0;
  }
  .melody-name { font-size: 14px; color: #d8b25c; margin-bottom: 12px; }
  .message {
    font-size: 15px; line-height: 1.75; color: #e8d9b8;
    white-space: pre-wrap; word-break: break-word;
    margin: 0 auto 18px; max-width: 42ch;
  }
  .stage {
    background: linear-gradient(180deg, #1c110a, #120b06);
    border: 1px solid rgba(212,175,55,.30);
    border-radius: 12px;
    padding: 12px 10px 10px;
  }
  canvas { width: 100%; display: block; }
  .progress { height: 3px; background: rgba(212,175,55,.18); border-radius: 2px; margin-top: 10px; overflow: hidden; }
  .progress > div { height: 100%; width: 0%; background: linear-gradient(90deg, #a87f1f, #f0cd6a); }
  .controls { margin-top: 20px; display: flex; align-items: center; justify-content: center; gap: 16px; }
  #playBtn {
    width: 72px; height: 72px; border-radius: 50%;
    border: 1px solid #e8c95c;
    background: radial-gradient(120% 120% at 32% 28%, #f4d878 0%, #c9a227 45%, #8a6a14 100%);
    color: #2a1c05; font-size: 27px; line-height: 1;
    box-shadow: 0 8px 22px rgba(0,0,0,.5), inset 0 2px 3px rgba(255,255,255,.55), inset 0 -4px 8px rgba(60,40,0,.45);
    cursor: pointer; -webkit-tap-highlight-color: transparent;
  }
  #playBtn:active { transform: scale(.96); }
  .hint { font-size: 12px; color: rgba(232,217,184,.55); }
  .meta { margin-top: 16px; font-size: 12px; color: rgba(232,217,184,.5); }
  .foot { margin-top: 18px; font-size: 11px; letter-spacing: .18em; color: rgba(201,162,39,.55); }
</style>
</head>
<body>
  <main class="card">
    <div class="brand">Duo Music Box</div>
    <h1 id="giftTitle">八音盒礼物</h1>
    <div class="melody-name" id="melodyName"></div>
    <p class="message" id="giftMessage"></p>
    <div class="stage">
      <canvas id="pins"></canvas>
      <div class="progress"><div id="bar"></div></div>
    </div>
    <div class="controls">
      <button id="playBtn" aria-label="播放">▶</button>
    </div>
    <div class="hint" id="hint">点播放键，八音盒就转起来了</div>
    <div class="meta" id="meta"></div>
    <div class="foot">无需安装 App · 本文件离线可播放</div>
  </main>
<script>
"use strict";
const GIFT = /*__GIFT__*/null;
const FREQS = [523.25, 587.33, 659.25, 698.46, 783.99, 880.00, 987.77, 1046.50];
const NOTE_NAMES = ["C5","D5","E5","F5","G5","A5","B5","C6"];
const PARTIALS = [[1.00,1.00,0.85],[2.01,0.10,0.45],[3.98,0.34,0.30],[9.24,0.13,0.13],[16.80,0.05,0.06]];

document.title = (GIFT.title || "八音盒礼物") + " · " + GIFT.melodyName;
document.getElementById("giftTitle").textContent = GIFT.title || "八音盒礼物";
document.getElementById("melodyName").textContent = "♪ " + GIFT.melodyName + " · " + GIFT.tempo + " BPM";
document.getElementById("giftMessage").textContent = GIFT.message || "";
document.getElementById("meta").textContent = GIFT.stepCount + " 步 · 8 音 · 与 App 相同的合成音色";

const stepDur = 60 / GIFT.tempo / 2;
const eventsByStep = new Map();
for (const e of GIFT.events) {
  if (!eventsByStep.has(e[0])) eventsByStep.set(e[0], []);
  eventsByStep.get(e[0]).push(e);
}

let ctx = null, master = null, noiseBuf = null;
let playing = false, timer = null;
let nextStep = 0, nextStepTime = 0, loopStart = 0;
let flashes = [];

function ensureAudio() {
  if (ctx) return;
  ctx = new (window.AudioContext || window.webkitAudioContext)();
  master = ctx.createGain();
  master.gain.value = 0.9;
  master.connect(ctx.destination);
  noiseBuf = ctx.createBuffer(1, Math.floor(ctx.sampleRate * 0.03), ctx.sampleRate);
  const d = noiseBuf.getChannelData(0);
  for (let i = 0; i < d.length; i++) d[i] = (Math.random() * 2 - 1) * (1 - i / d.length);
}

function playTone(pitch, at, velocity) {
  const f = FREQS[pitch];
  const vel = velocity || 0.85;
  for (const [ratio, amp, tau] of PARTIALS) {
    const osc = ctx.createOscillator();
    osc.type = "sine";
    osc.frequency.value = f * ratio;
    const g = ctx.createGain();
    g.gain.setValueAtTime(0.0001, at);
    g.gain.exponentialRampToValueAtTime(Math.max(0.0002, amp * vel * 0.30), at + 0.003);
    g.gain.exponentialRampToValueAtTime(0.0001, at + Math.min(1.8, tau * 5.2));
    osc.connect(g); g.connect(master);
    osc.start(at); osc.stop(at + 1.85);
  }
  const src = ctx.createBufferSource();
  src.buffer = noiseBuf;
  const bp = ctx.createBiquadFilter();
  bp.type = "bandpass"; bp.frequency.value = 3200; bp.Q.value = 0.9;
  const ng = ctx.createGain();
  ng.gain.setValueAtTime(0.14 * vel, at);
  ng.gain.exponentialRampToValueAtTime(0.0001, at + 0.03);
  src.connect(bp); bp.connect(ng); ng.connect(master);
  src.start(at); src.stop(at + 0.04);
  flashes.push({ step: nextStep, pitch: pitch, at: at });
}

function schedule() {
  while (nextStepTime < ctx.currentTime + 0.15) {
    const evs = eventsByStep.get(nextStep);
    if (evs) for (const e of evs) playTone(e[1], nextStepTime, e[3]);
    if (nextStep === 0) loopStart = nextStepTime;
    nextStep += 1;
    if (nextStep >= GIFT.stepCount) nextStep = 0;
    nextStepTime += stepDur;
  }
}

const btn = document.getElementById("playBtn");
const hint = document.getElementById("hint");
btn.addEventListener("click", async () => {
  ensureAudio();
  if (!playing) {
    await ctx.resume();
    playing = true;
    btn.textContent = "❚❚";
    hint.textContent = "正在播放 · 循环中";
    if (nextStepTime < ctx.currentTime) { nextStep = 0; nextStepTime = ctx.currentTime + 0.06; loopStart = nextStepTime; flashes = []; }
    schedule();
    timer = setInterval(schedule, 40);
  } else {
    playing = false;
    btn.textContent = "▶";
    hint.textContent = "已暂停 · 再点继续";
    clearInterval(timer);
    await ctx.suspend();
  }
});

// —— 音钉图（与 App 编曲表格同一布局：横轴步进、纵轴音高 C6 在上）——
const canvas = document.getElementById("pins");
const c2d = canvas.getContext("2d");
function layout() {
  const w = canvas.clientWidth, h = Math.round(w * 0.46);
  const dpr = window.devicePixelRatio || 1;
  canvas.width = w * dpr; canvas.height = h * dpr;
  canvas.style.height = h + "px";
  c2d.setTransform(dpr, 0, 0, dpr, 0, 0);
}
window.addEventListener("resize", layout);

function draw() {
  const w = canvas.clientWidth, h = canvas.clientHeight;
  const cols = GIFT.stepCount, rows = 8;
  const padL = 8, padR = 8, padT = 8, padB = 8;
  const cw = (w - padL - padR) / cols, rh = (h - padT - padB) / rows;
  c2d.clearRect(0, 0, w, h);
  // 小节分隔（每 8 步）
  c2d.strokeStyle = "rgba(212,175,55,0.13)";
  c2d.lineWidth = 1;
  for (let s = 0; s <= cols; s += 8) {
    c2d.beginPath();
    c2d.moveTo(padL + s * cw, padT - 3);
    c2d.lineTo(padL + s * cw, h - padB + 3);
    c2d.stroke();
  }
  let nowStep = -1;
  if (ctx && playing) {
    const pos = (ctx.currentTime - loopStart) / stepDur;
    nowStep = Math.floor(pos) % cols;
    document.getElementById("bar").style.width = ((pos % cols) / cols * 100) + "%";
  }
  if (nowStep >= 0) {
    c2d.fillStyle = "rgba(240,205,106,0.10)";
    c2d.fillRect(padL + nowStep * cw, padT - 4, cw, h - padT - padB + 8);
  }
  const now = ctx ? ctx.currentTime : 0;
  flashes = flashes.filter(f => now - f.at < 0.30);
  for (const e of GIFT.events) {
    const x = padL + (e[0] + 0.5) * cw;
    const y = padT + (7 - e[1] + 0.5) * rh;
    const len = Math.max(1, e[2]) * cw;
    const flash = flashes.some(f => f.step === e[0] && f.pitch === e[1]);
    c2d.fillStyle = flash ? "#ffe98a" : "rgba(224,183,74,0.85)";
    c2d.strokeStyle = flash ? "#fff3b0" : "rgba(120,84,20,0.9)";
    c2d.lineWidth = 1;
    c2d.beginPath();
    c2d.arc(x, y, Math.min(4.2, cw * 0.30), 0, Math.PI * 2);
    c2d.fill(); c2d.stroke();
    if (e[2] > 1) {
      c2d.fillStyle = flash ? "rgba(255,233,138,.75)" : "rgba(224,183,74,.40)";
      c2d.fillRect(x, y - 1, len - cw * 0.5, 2);
    }
  }
  requestAnimationFrame(draw);
}
layout();
requestAnimationFrame(draw);
</script>
</body>
</html>

"""#

    public static func html(for package: GiftPackage) -> String {
        let melody = package.melodySnapshot
        let events: [[Double]] = melody.events
            .sorted { $0.step < $1.step }
            .map { [Double($0.step), Double($0.pitchIndex), Double($0.durationSteps), $0.velocity] }
        let dict: [String: Any] = [
            "title": package.title,
            "melodyName": package.melodyName,
            "message": package.message,
            "tempo": melody.tempoBPM,
            "stepCount": melody.stepCount,
            "events": events,
        ]
        let jsonData = (try? JSONSerialization.data(withJSONObject: dict)) ?? Data("{}".utf8)
        let json = String(data: jsonData, encoding: .utf8) ?? "{}"
        return template.replacingOccurrences(of: "/*__GIFT__*/null", with: json)
    }

    /// 写到临时目录并返回 URL（分享面板与 FileRepresentation 共用）。
    public static func fileURL(for package: GiftPackage) throws -> URL {
        let safeName = package.melodyName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("八音盒礼物-\(safeName).html")
        try html(for: package).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

/// ShareLink 用的网页礼物导出（.html 文件）。
public struct WebGiftFile: Transferable {
    public var package: GiftPackage

    public init(package: GiftPackage) {
        self.package = package
    }

    public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .html) { item in
            SentTransferredFile(try GiftWebPage.fileURL(for: item.package))
        }
    }
}

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Headphones with AVRCP absolute volume (Bose 700 etc.) change the Bluetooth
// sink's volume directly in PipeWire; no key event reaches Hyprland, so the
// XF86Audio* binds never run omarchy-audio-output-volume and no OSD appears.
// Watch the default sink instead and show the same OSD the keys show.
Item {
  id: root

  property var shell: null

  // Only react to Bluetooth outputs so app/panel changes on other sinks stay quiet.
  property bool bluetoothOnly: true

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property bool sinkReady: !!(sink && sink.ready && sink.audio)
  readonly property bool watched: sinkReady
    && (!bluetoothOnly || String(sink.name || "").indexOf("bluez_output") === 0)

  // Last state seen per sink, so the initial bind/sink switch doesn't pop the OSD.
  property var lastSink: null
  property int lastPercent: -1
  property bool lastMuted: false
  // Ignore the volume settling that happens right after a sink appears or
  // becomes the default (BT reconnects re-sync absolute volume).
  property bool settling: true

  PwObjectTracker { objects: root.sink ? [root.sink] : [] }

  Timer {
    id: settleTimer
    interval: 1500
    onTriggered: root.settling = false
  }

  function snapshot() {
    root.lastSink = root.sink
    root.lastPercent = root.sinkReady ? Math.round(root.sink.audio.volume * 100) : -1
    root.lastMuted = root.sinkReady ? root.sink.audio.muted : false
  }

  function check() {
    if (!root.sinkReady) return
    if (root.sink !== root.lastSink) {
      root.settling = true
      settleTimer.restart()
      snapshot()
      return
    }
    var percent = Math.round(root.sink.audio.volume * 100)
    var muted = root.sink.audio.muted
    if (percent === root.lastPercent && muted === root.lastMuted) return
    root.lastPercent = percent
    root.lastMuted = muted
    if (root.settling || !root.watched) return

    var icon = (muted || percent === 0) ? "volume-muted" : "volume-high"
    Quickshell.execDetached(["omarchy-osd", "-i", icon, "-p", String(Math.min(percent, 100))])
  }

  onSinkReadyChanged: check()
  onSinkChanged: check()

  Connections {
    target: root.sinkReady ? root.sink.audio : null
    function onVolumesChanged() { root.check() }
    function onMutedChanged() { root.check() }
  }

  Component.onCompleted: {
    snapshot()
    settleTimer.restart()
  }
}

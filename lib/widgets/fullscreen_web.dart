// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void requestNativeFullscreen() {
  final doc = html.document;

  // If already fullscreen, exit instead (toggle behaviour)
  if (doc.fullscreenElement != null) {
    doc.exitFullscreen();
    return;
  }

  // Try the <video> element first, fall back to <body>
  final video = doc.querySelector('video');
  final target = video ?? doc.body;
  target?.requestFullscreen();
}

void exitNativeFullscreen() {
  html.document.exitFullscreen();
}

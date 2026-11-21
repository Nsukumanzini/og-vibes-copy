{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    // Serve CanvasKit from this deployment so startup does not depend on
    // fetching the renderer from a third-party host.
    canvasKitBaseUrl: 'canvaskit/',
  },
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}}
  },
});

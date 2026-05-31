{{flutter_js}}
{{flutter_build_config}}

const serviceWorkerVersion = {{flutter_service_worker_version}};
const shouldUseLocalCanvasKit =
  /^(localhost|127(?:\.\d{1,3}){3}|::1)$/.test(window.location.hostname);

const loadOptions = {
  config: {
    // Keep local Chrome runs off the network by loading CanvasKit from the SDK.
    canvasKitBaseUrl: shouldUseLocalCanvasKit ? 'canvaskit/' : undefined,
  },
};

if (serviceWorkerVersion !== null) {
  loadOptions.serviceWorkerSettings = {
    serviceWorkerVersion,
  };
}

_flutter.loader.load(loadOptions);

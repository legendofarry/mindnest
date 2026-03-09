{{flutter_js}}
{{flutter_build_config}}

const searchParams = new URLSearchParams(window.location.search);
const renderer = searchParams.get('renderer') || 'canvaskit';

const config =
  renderer === 'skwasm'
      ? {
          renderer: 'skwasm',
          forceSingleThreadedSkwasm: true,
        }
      : {
          renderer: 'canvaskit',
          canvasKitForceCpuOnly: true,
          canvasKitVariant: 'auto',
        };

_flutter.loader.load({
  config,
});

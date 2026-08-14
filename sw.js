// Service worker minimo: cachea los archivos estaticos para que la app
// abra rapido y funcione como "app instalada". Los datos (reportes)
// siempre se piden en vivo a Supabase, no se guardan offline.
//
// IMPORTANTE: la pagina principal (HTML) usa estrategia "red primero,
// cache de respaldo" -- asi cada vez que publicamos un cambio, se ve de
// inmediato en vez de quedar atascado con una version vieja guardada.
const CACHE = 'mascota-sos-v2';
const ARCHIVOS = ['./manifest.json', './icon-192.png', './icon-512.png'];

self.addEventListener('install', (ev) => {
  ev.waitUntil(caches.open(CACHE).then(c => c.addAll(ARCHIVOS)));
  self.skipWaiting();
});

self.addEventListener('activate', (ev) => {
  ev.waitUntil(
    caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
  );
  self.clients.claim();
});

self.addEventListener('fetch', (ev) => {
  if (ev.request.url.includes('supabase.co')) return; // datos: siempre red
  const esNavegacion = ev.request.mode === 'navigate' || ev.request.destination === 'document';
  if (esNavegacion) {
    // HTML: intenta la red primero (para ver cambios nuevos de inmediato);
    // si no hay internet, usa la copia guardada como respaldo.
    ev.respondWith(
      fetch(ev.request).then(res => {
        caches.open(CACHE).then(c => c.put(ev.request, res.clone()));
        return res;
      }).catch(() => caches.match(ev.request))
    );
    return;
  }
  // Archivos estaticos (iconos, manifest): cache primero, mas rapido.
  ev.respondWith(
    caches.match(ev.request).then(cached => cached || fetch(ev.request))
  );
});

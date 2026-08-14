// Service worker minimo: solo cachea los archivos estaticos para que la
// app abra rapido y funcione como "app instalada". Los datos (reportes)
// siempre se piden en vivo a Supabase, no se guardan offline.
const CACHE = 'mascota-sos-v1';
const ARCHIVOS = ['./', './index.html', './manifest.json', './icon-192.png', './icon-512.png'];

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
  // Peticiones a Supabase (datos) siempre van a la red, nunca a cache.
  if (ev.request.url.includes('supabase.co')) return;
  ev.respondWith(
    caches.match(ev.request).then(cached => cached || fetch(ev.request))
  );
});

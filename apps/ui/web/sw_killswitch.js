// Заглушка служебного воркера: кладётся поверх сгенерированного
// flutter_service_worker.js после сборки (`flutter build web` пишет туда
// пустой файл и перезаписал бы этот код).
//
// Файл оставлен намеренно. У браузеров, которые открывали сервис раньше,
// воркер Flutter уже зарегистрирован и продолжает отдавать закешированную
// сборку — обновление службы для них не видно. Браузер периодически
// перезапрашивает этот файл, получает код ниже и снимает регистрацию сам.
self.addEventListener('install', function () {
  self.skipWaiting();
});

self.addEventListener('activate', function (event) {
  event.waitUntil(
    (async function () {
      const keys = await caches.keys();
      await Promise.all(keys.map(function (key) { return caches.delete(key); }));
      await self.registration.unregister();
      const windows = await self.clients.matchAll({ type: 'window' });
      windows.forEach(function (client) { client.navigate(client.url); });
    })(),
  );
});

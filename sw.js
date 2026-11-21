function safeNotificationUrl(value) {
  try {
    const url = new URL(typeof value === 'string' ? value : './', self.location.origin);
    return url.origin === self.location.origin ? url.href : new URL('./', self.location.origin).href;
  } catch {
    return new URL('./', self.location.origin).href;
  }
}

self.addEventListener('push', event => {
  let data = { title: 'ATINA', body: 'Tens uma nova notificação.', url: './' };
  try {
    data = { ...data, ...event.data.json() };
  } catch {}
  event.waitUntil(self.registration.showNotification(data.title || 'ATINA', {
    body: data.body || 'Nova notificação',
    data: { url: safeNotificationUrl(data.url) },
    tag: data.tag || 'atina-push',
    renotify: false
  }));
});

self.addEventListener('notificationclick', event => {
  event.notification.close();
  const url = safeNotificationUrl(event.notification.data?.url);
  event.waitUntil(clients.matchAll({ type: 'window', includeUncontrolled: true }).then(async list => {
    for (const client of list) {
      if (client.url && new URL(client.url).origin === self.location.origin && 'focus' in client) {
        try {
          if ('navigate' in client) await client.navigate(url);
          return await client.focus();
        } catch {}
      }
    }
    return clients.openWindow(url);
  }));
});

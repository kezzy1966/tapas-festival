const operationalRoutes = new Set(['/admin', '/reset-password']);

export default defineNuxtRouteMiddleware((to) => {
  const holdingMode = String(useRuntimeConfig().public.holdingMode).toLowerCase() === 'true';
  if (!holdingMode || operationalRoutes.has(to.path) || to.path === '/') return;
  return navigateTo('/', { replace: true });
});

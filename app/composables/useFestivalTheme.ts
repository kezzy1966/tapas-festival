export type FestivalTheme = 'light' | 'dark';

const storageKey = 'festival-theme';

export function useFestivalTheme() {
  const theme = useState<FestivalTheme>('festival-theme', () => 'light');

  const applyTheme = (value: FestivalTheme) => {
    theme.value = value;
    if (!import.meta.client) return;
    document.documentElement.classList.toggle('dark', value === 'dark');
    document.documentElement.style.colorScheme = value;
  };

  const setTheme = (value: FestivalTheme) => {
    applyTheme(value);
    if (import.meta.client) localStorage.setItem(storageKey, value);
  };

  const toggleTheme = () => setTheme(theme.value === 'dark' ? 'light' : 'dark');

  onMounted(() => {
    const saved = localStorage.getItem(storageKey);
    const systemTheme: FestivalTheme = window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
    applyTheme(saved === 'dark' || saved === 'light' ? saved : systemTheme);
  });

  return { theme, setTheme, toggleTheme };
}

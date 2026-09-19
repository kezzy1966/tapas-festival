import { onMounted, onUnmounted, ref } from 'vue';

export type OpeningHoursState = 'open' | 'closed' | 'unavailable';
const MADRID_TIME_ZONE = 'Europe/Madrid';
const WEEKDAY_NUMBERS: Record<string, number> = { Monday: 1, Tuesday: 2, Wednesday: 3, Thursday: 4, Friday: 5, Saturday: 6, Sunday: 7 };

type Period = { start: number; end: number };
type ParsedHours = Record<number, Period[]>;

function parseTime(value: unknown) {
  if (typeof value !== 'string' || !/^\d{1,2}:\d{2}$/.test(value)) return null;
  const [hour, minute] = value.split(':').map(Number);
  return hour <= 23 && minute <= 59 ? hour * 60 + minute : null;
}
function parseHours(value: unknown): ParsedHours | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const entries = Object.entries(value as Record<string, unknown>);
  if (!entries.length || entries.some(([day]) => !/^[1-7]$/.test(day))) return null;
  const parsed: ParsedHours = {};
  for (const [day, rawPeriods] of entries) {
    if (!Array.isArray(rawPeriods)) return null;
    parsed[Number(day)] = [];
    for (const rawPeriod of rawPeriods) {
      if (!Array.isArray(rawPeriod) || rawPeriod.length !== 2) return null;
      const start = parseTime(rawPeriod[0]);
      const end = parseTime(rawPeriod[1]);
      if (start == null || end == null || start === end) return null;
      parsed[Number(day)].push({ start, end });
    }
  }
  return parsed;
}
function madridNow(now: Date) {
  const parts = new Intl.DateTimeFormat('en-GB', { timeZone: MADRID_TIME_ZONE, weekday: 'long', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(now);
  const values = Object.fromEntries(parts.filter((part) => part.type !== 'literal').map((part) => [part.type, part.value]));
  return { weekday: WEEKDAY_NUMBERS[values.weekday], minutes: Number(values.hour) * 60 + Number(values.minute) };
}

export function openingHoursStatus(hours: unknown, now = new Date()): OpeningHoursState {
  const parsed = parseHours(hours);
  if (!parsed) return 'unavailable';
  const current = madridNow(now);
  if (!current.weekday || !Number.isFinite(current.minutes)) return 'unavailable';
  const previousDay = current.weekday === 1 ? 7 : current.weekday - 1;
  for (const period of parsed[current.weekday] || []) {
    if (period.end > period.start && current.minutes >= period.start && current.minutes < period.end) return 'open';
    if (period.end < period.start && current.minutes >= period.start) return 'open';
  }
  for (const period of parsed[previousDay] || []) {
    if (period.end < period.start && current.minutes < period.end) return 'open';
  }
  return 'closed';
}

export function useOpeningHoursStatus() {
  const now = ref(new Date());
  let timer: ReturnType<typeof setInterval> | undefined;
  onMounted(() => { timer = window.setInterval(() => { now.value = new Date(); }, 60_000); });
  onUnmounted(() => { if (timer) window.clearInterval(timer); });
  return { now, openingHoursStatus };
}

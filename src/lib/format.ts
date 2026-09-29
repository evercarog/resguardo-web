const LOCALE = "es";

export function formatBytes(n?: number | null) {
  if (n == null) return "—";
  const units = ["B", "KB", "MB", "GB", "TB"];
  let i = 0;
  while (n >= 1024 && i < units.length - 1) {
    n /= 1024;
    i++;
  }
  return `${n.toLocaleString(LOCALE, { maximumFractionDigits: i === 0 ? 0 : 1 })} ${units[i]}`;
}

export const formatNumber = (n: number) => n.toLocaleString(LOCALE);

export function formatDuration(seconds?: number | null) {
  if (seconds == null) return "—";
  const s = Math.round(seconds);
  if (s < 60) return `${s} s`;
  const m = Math.floor(s / 60);
  // "12 min" mejor que "12 min 0 s"; a partir de 10 min los segundos sobran.
  if (m < 60) return s % 60 === 0 || m >= 10 ? `${m} min` : `${m} min ${s % 60} s`;
  return `${Math.floor(m / 60)} h ${m % 60} min`;
}

const dateFmt = new Intl.DateTimeFormat(LOCALE, { dateStyle: "medium", timeStyle: "short" });
export const formatDate = (iso: string) => dateFmt.format(new Date(iso));

const timeFmt = new Intl.DateTimeFormat(LOCALE, { hour: "2-digit", minute: "2-digit" });
export const formatTime = (iso: string) => timeFmt.format(new Date(iso));

const dayFmt = new Intl.DateTimeFormat(LOCALE, { weekday: "long", day: "numeric", month: "long" });
const dayYearFmt = new Intl.DateTimeFormat(LOCALE, { weekday: "long", day: "numeric", month: "long", year: "numeric" });

const startOfDay = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();

/** "Hoy", "Ayer" o la fecha larga, para agrupar snapshots por día. */
export function formatDay(iso: string) {
  const d = new Date(iso);
  const days = Math.round((startOfDay(new Date()) - startOfDay(d)) / 86_400_000);
  if (days === 0) return "Hoy";
  if (days === 1) return "Ayer";
  const text = (d.getFullYear() === new Date().getFullYear() ? dayFmt : dayYearFmt).format(d);
  return text.charAt(0).toUpperCase() + text.slice(1);
}

const rtf = new Intl.RelativeTimeFormat(LOCALE, { numeric: "auto" });

/** "hace 5 minutos", "ayer", "hace 3 meses"… (`now` permite refrescarlo con un reloj). */
export function formatRelative(iso: string | number, now = Date.now()) {
  const diff = Math.min(0, new Date(iso).getTime() - now) / 1000;
  const abs = Math.abs(diff);
  if (abs < 60) return "hace un momento";
  if (abs < 3600) return rtf.format(Math.round(diff / 60), "minute");
  if (abs < 86_400) return rtf.format(Math.round(diff / 3600), "hour");
  if (abs < 86_400 * 30) return rtf.format(Math.round(diff / 86_400), "day");
  if (abs < 86_400 * 365) return rtf.format(Math.round(diff / (86_400 * 30)), "month");
  return rtf.format(Math.round(diff / (86_400 * 365)), "year");
}

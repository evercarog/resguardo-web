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

// ---------- Fechas: siempre en la hora de Colombia ----------
// Los clientes están en Colombia: las horas y los días se muestran en
// America/Bogota aunque la web se abra desde otro país. Colombia no tiene
// horario de verano (UTC−5 todo el año desde 1993), así que las cuentas de
// días se hacen con un desfase fijo; los textos usan Intl con la zona.

export const TIME_ZONE = "America/Bogota";
const OFFSET = -5 * 3_600_000;
const DAY = 86_400_000;

type When = string | number | Date;
const ms = (t: When) => (t instanceof Date ? t.getTime() : typeof t === "number" ? t : new Date(t).getTime());
const pad = (n: number) => String(n).padStart(2, "0");

/** Fecha y hora «de pared» en Bogotá. `month` 0–11; `weekday` 0 = lunes … 6 = domingo. */
export function bogota(t: When) {
  const d = new Date(ms(t) + OFFSET);
  return {
    year: d.getUTCFullYear(),
    month: d.getUTCMonth(),
    day: d.getUTCDate(),
    hours: d.getUTCHours(),
    minutes: d.getUTCMinutes(),
    weekday: (d.getUTCDay() + 6) % 7
  };
}

/** Instante de una hora de Bogotá (día 32, mes 12… se normalizan como en Date). */
export const bogotaTime = (year: number, month: number, day: number, hours = 0, minutes = 0) =>
  new Date(Date.UTC(year, month, day, hours, minutes) - OFFSET);

/** Medianoche (Bogotá) del día de `t`, desplazada `offsetDays` días. */
export function startOfDay(t: When, offsetDays = 0) {
  const b = bogota(t);
  return bogotaTime(b.year, b.month, b.day + offsetDays);
}

/** Clave del día en Bogotá: «2026-09-30». */
export function dayKey(t: When) {
  const b = bogota(t);
  return `${b.year}-${pad(b.month + 1)}-${pad(b.day)}`;
}

/** Mediodía (Bogotá) del día de una clave «AAAA-MM-DD». */
export function fromDayKey(key: string) {
  const [y, m, d] = key.split("-").map(Number);
  return bogotaTime(y, m - 1, d, 12);
}

const fmt = (o: Intl.DateTimeFormatOptions) => new Intl.DateTimeFormat(LOCALE, { timeZone: TIME_ZONE, ...o });

const dateFmt = fmt({ dateStyle: "medium", timeStyle: "short" });
/** «30 sept 2026, 17:00» */
export const formatDate = (t: When) => dateFmt.format(ms(t));

const timeFmt = fmt({ hour: "2-digit", minute: "2-digit" });
/** «17:00» */
export const formatTime = (t: When) => timeFmt.format(ms(t));

const dayShortFmt = fmt({ weekday: "short", day: "numeric", month: "short" });
/** «mié, 30 sept» */
export const formatDayShort = (t: When) => dayShortFmt.format(ms(t));

const monthFmt = fmt({ month: "long", year: "numeric" });
/** «Septiembre de 2026» (con la primera letra en mayúscula). */
export function formatMonth(t: When) {
  const text = monthFmt.format(ms(t));
  return text.charAt(0).toUpperCase() + text.slice(1);
}

const dayFmt = fmt({ weekday: "long", day: "numeric", month: "long" });
const dayYearFmt = fmt({ weekday: "long", day: "numeric", month: "long", year: "numeric" });

/** "Hoy", "Ayer" o la fecha larga, para agrupar por día (días de Bogotá). */
export function formatDay(t: When, now = Date.now()) {
  const days = Math.round((startOfDay(now).getTime() - startOfDay(t).getTime()) / DAY);
  if (days === 0) return "Hoy";
  if (days === 1) return "Ayer";
  const text = (bogota(t).year === bogota(now).year ? dayFmt : dayYearFmt).format(ms(t));
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

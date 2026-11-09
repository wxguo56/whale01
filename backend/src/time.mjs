const CN_DIGITS = { 零: 0, 一: 1, 二: 2, 两: 2, 三: 3, 四: 4, 五: 5, 六: 6, 七: 7, 八: 8, 九: 9 };

function pad(value) {
  return String(value).padStart(2, "0");
}

export function zonedParts(date, timeZone) {
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    hour12: false,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit"
  });
  const parts = Object.fromEntries(formatter.formatToParts(date).map((part) => [part.type, part.value]));
  return {
    year: Number(parts.year),
    month: Number(parts.month),
    day: Number(parts.day),
    hour: Number(parts.hour === "24" ? "0" : parts.hour),
    minute: Number(parts.minute),
    second: Number(parts.second)
  };
}

export function offsetMinutesAt(date, timeZone) {
  const parts = zonedParts(date, timeZone);
  const asUtc = Date.UTC(parts.year, parts.month - 1, parts.day, parts.hour, parts.minute, parts.second);
  return Math.round((asUtc - date.getTime()) / 60000);
}

export function formatOffset(minutes) {
  const sign = minutes >= 0 ? "+" : "-";
  const abs = Math.abs(minutes);
  return `${sign}${pad(Math.floor(abs / 60))}:${pad(abs % 60)}`;
}

export function toLocalIso({ year, month, day, hour, minute }, offset) {
  return `${year}-${pad(month)}-${pad(day)}T${pad(hour)}:${pad(minute)}:00${formatOffset(offset)}`;
}

export function addDaysToDate({ year, month, day }, days) {
  const shifted = new Date(Date.UTC(year, month - 1, day + days));
  return { year: shifted.getUTCFullYear(), month: shifted.getUTCMonth() + 1, day: shifted.getUTCDate() };
}

function chineseNumber(text) {
  if (/^\d+$/.test(text)) return Number(text);
  if (text === "十") return 10;
  if (text.startsWith("十")) return 10 + (CN_DIGITS[text[1]] ?? 0);
  if (text.includes("十")) {
    const [tens, ones] = text.split("十");
    return (CN_DIGITS[tens] ?? 1) * 10 + (CN_DIGITS[ones] ?? 0);
  }
  let value = 0;
  for (const char of text) value = value * 10 + (CN_DIGITS[char] ?? 0);
  return value;
}

const DATE_WORDS = { 今天: 0, 明天: 1, 后天: 2, 大后天: 3 };

export function parseReminderIntent(text, nowIso, timeZone) {
  const now = new Date(nowIso);
  const base = zonedParts(now, timeZone);
  const offset = offsetMinutesAt(now, timeZone);

  const dateMatch = /(大后天|后天|明天|今天)/.exec(text);
  const timeMatch = /(凌晨|早上|上午|中午|下午|傍晚|晚上)?\s*(\d{1,2}|[零一二两三四五六七八九十]{1,3})\s*[点时](半|一刻|三刻|[零一二三四五]刻|\d{1,2}分)?/.exec(text);

  let dueAt = null;
  let needsTime = false;
  let needsPeriod = false;
  let parsedHour = null;
  let parsedDate = null;

  if (dateMatch || timeMatch) {
    const dayShift = dateMatch ? DATE_WORDS[dateMatch[1]] : 0;
    const dateParts = addDaysToDate(base, dayShift);
    parsedDate = `${dateParts.year}-${pad(dateParts.month)}-${pad(dateParts.day)}`;

    if (!timeMatch) {
      needsTime = true;
    } else {
      const period = timeMatch[1] ?? null;
      let hour = chineseNumber(timeMatch[2]);
      const minuteToken = timeMatch[3] ?? null;
      let minute = 0;
      if (minuteToken === "半") minute = 30;
      else if (minuteToken === "一刻") minute = 15;
      else if (minuteToken === "三刻") minute = 45;
      else if (minuteToken?.endsWith("分")) minute = chineseNumber(minuteToken.slice(0, -1));
      else if (minuteToken?.endsWith("刻")) minute = chineseNumber(minuteToken.slice(0, -1)) * 15;

      if (period) {
        if (["下午", "傍晚", "晚上"].includes(period) && hour < 12) hour += 12;
        if (period === "中午" && hour < 11) hour += 12;
        if (["凌晨", "早上", "上午"].includes(period) && hour === 12) hour = 0;
      } else if (hour >= 1 && hour <= 12) {
        needsPeriod = true;
      }

      parsedHour = hour;
      if (hour >= 0 && hour <= 23 && !needsPeriod) {
        dueAt = toLocalIso({ ...dateParts, hour, minute }, offset);
      }
    }
  }

  let title = text
    .replace(/(大后天|后天|明天|今天)/g, " ")
    .replace(/(凌晨|早上|上午|中午|下午|傍晚|晚上)?\s*(\d{1,2}|[零一二两三四五六七八九十]{1,3})\s*[点时](半|一刻|三刻|[零一二三四五]刻|\d{1,2}分)?/g, " ")
    .replace(/^(帮我|请|麻烦)?\s*(提醒我|提醒|叫我|记得|记一下|创建待办[:：]?|待办[:：]?|新建待办[:：]?)\s*/g, "")
    .replace(/^[，,：:\s]+|[，,。.\s]+$/g, "")
    .trim();

  if (!title) title = "提醒";

  return {
    kind: "reminder",
    title,
    dueAt,
    needsTime,
    needsPeriod,
    parsedHour,
    date: parsedDate
  };
}

export function isReminderIntent(text) {
  return /提醒|待办|记得/.test(text);
}

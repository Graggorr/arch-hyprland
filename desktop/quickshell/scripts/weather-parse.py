#!/usr/bin/env python3
"""Turn a sinoptik.ua 10-day page into the island's weather JSON.

Reads the page HTML on stdin, writes the reading on stdout and
"sunset\\nsunrise" on stderr (weather.sh caches that for the lock screen).

sinoptik only publishes 4 slots a day past tomorrow, so those days take
their hours from Open-Meteo at the coordinates sinoptik reports; if that
fetch fails they keep sinoptik's slots.

sinoptik embeds its whole forecast as one JSON object in the markup, so this
reads structured data rather than scraping rendered temperatures. Conditions
are Foreca symbols: the hundreds digit is cloud cover, a non-zero tens digit
means precipitation, and the units digit is its type.
"""
import datetime
import json
import os
import sys
import urllib.request

MARK = '{"ui":{"defaultLocationConfigShown"'

# band -> (label, day glyph, night glyph, day colour, night colour)
BANDS = {
    0: ("Clear",             "", "", "#f9d67a", "#b9a6f7"),
    1: ("Mostly clear",      "", "", "#f9d67a", "#b9a6f7"),
    2: ("Partly cloudy",     "", "", "#cfd6e4", "#cfd6e4"),
    3: ("Cloudy",            "", "", "#aab3c2", "#aab3c2"),
    4: ("Overcast",          "", "", "#aab3c2", "#aab3c2"),
    5: ("Thin high clouds",  "", "", "#cfd6e4", "#cfd6e4"),
    6: ("Fog",               "", "", "#9fb4cf", "#9fb4cf"),
}


def extract(html):
    if MARK not in html:
        raise ValueError("forecast payload not found")
    start = html.index(MARK)
    depth = 0
    instr = esc = False
    for j in range(start, len(html)):
        c = html[j]
        if instr:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                instr = False
            continue
        if c == '"':
            instr = True
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return json.loads(html[start:j + 1])
    raise ValueError("unterminated payload")


def decode(code, night=False):
    code = int(code or 0)
    band = min(6, code // 100)
    precip = (code % 100) // 10
    kind = code % 10
    label, day_g, night_g, day_h, night_h = BANDS[band]
    if precip:
        if kind >= 4:
            return "Thunderstorm", "", "#f9c74f"
        if kind == 3:
            return "Snow", "", "#e6f0ff"
        if kind == 2:
            return "Sleet", "", "#a9d6ec"
        return ("Heavy rain" if precip >= 3 else "Rain"), \
               ("" if night else ""), "#74c7ec"
    return label, (night_g if night else day_g), (night_h if night else day_h)


def hhmm(mins):
    mins = int(mins or 0)
    return "%02d:%02d" % (mins // 60, mins % 60)


def day_hours(day, sunrise, sunset):
    """The day's hourly rows as sinoptik gives them: 24 for today and
    tomorrow, 4 for later days (main() fills those from Open-Meteo)."""
    rise_h, set_h = int(sunrise[:2]), int(sunset[:2])
    out = []
    for h in day.get("hours") or []:
        hour = int(h.get("hour", 0))
        night = hour < rise_h or hour > set_h
        label, glyph, colour = decode(h.get("condition"), night)
        wind = (h.get("wind") or {}).get("speed", "")
        if wind != "":
            wind = str(round(float(wind) * 3.6))
        out.append({
            "hour": hour, "temp": str(h.get("temperature", "")),
            "feels": str(h.get("temperatureFeel", h.get("temperature", ""))),
            "desc": label, "icon": glyph, "hex": colour,
            "rain": str(h.get("precipitation", 0)), "wind": wind,
        })
    return out


OM_URL = ("https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s"
          "&hourly=temperature_2m,apparent_temperature,precipitation_probability,"
          "weather_code,wind_speed_10m,is_day&forecast_days=16&timezone=auto")


def wmo_to_foreca(code):
    """Open-Meteo's WMO weather code as the Foreca symbol decode() reads."""
    code = int(code or 0)
    if code >= 95:
        return 414
    if code in (56, 57, 66, 67):
        return 412
    if 71 <= code <= 77 or code in (85, 86):
        return 413
    if code in (65, 82):
        return 430
    if 51 <= code <= 82:
        return 410
    if code in (45, 48):
        return 600
    return {0: 0, 1: 100, 2: 200}.get(code, 400)


def open_meteo_hours(lat, lng):
    """{date: [24 hourly rows]} from Open-Meteo, or {} when it is unreachable."""
    try:
        with urllib.request.urlopen(OM_URL % (lat, lng), timeout=8) as r:
            h = json.load(r)["hourly"]
    except Exception:
        return {}
    by_day = {}
    for i, stamp in enumerate(h["time"]):
        date, clock = stamp.split("T")
        label, glyph, colour = decode(wmo_to_foreca(h["weather_code"][i]),
                                      not h["is_day"][i])
        temp = h["temperature_2m"][i]
        if temp is None:
            continue
        feels = h["apparent_temperature"][i]
        wind = h["wind_speed_10m"][i]
        by_day.setdefault(date, []).append({
            "hour": int(clock[:2]), "temp": str(round(temp)),
            "feels": str(round(feels if feels is not None else temp)),
            "desc": label, "icon": glyph, "hex": colour,
            "rain": str(h["precipitation_probability"][i] or 0),
            "wind": "" if wind is None else str(round(wind)),
        })
    return by_day


def main():
    data = extract(sys.stdin.read())["weather"]["data"]
    days = data.get("forecast") or []
    if not days:
        raise ValueError("no forecast days")

    today = days[0]
    sun = today.get("sunTime") or {}
    sunrise, sunset = hhmm(sun.get("sunrise")), hhmm(sun.get("sunset"))

    now_clock = datetime.datetime.now()
    night = not (sunrise <= now_clock.strftime("%H:%M") < sunset)

    nw = today.get("now") or {}
    hours = today.get("hours") or []
    hour = min(hours, key=lambda h: abs(h.get("hour", 0) - now_clock.hour)) if hours else {}

    desc, icon, hexv = decode(nw.get("condition", today.get("condition")), night)
    temp = nw.get("temperature", hour.get("temperature", 0))
    feels = nw.get("temperatureFeel", hour.get("temperatureFeel", temp))
    humidity = hour.get("humidity", "")

    wind = (hour.get("wind") or {}).get("speed", "")
    if wind != "":
        wind = str(round(float(wind) * 3.6))

    loc = data.get("location") or {}
    area = (loc.get("name") or loc.get("id")
            or os.environ.get("CITY", "")).replace("-", " ").title()

    forecast = []
    for d in days:
        label, glyph, colour = decode(d.get("condition"), False)
        t = d.get("temperature") or {}
        rain = max((h.get("precipitation", 0) for h in (d.get("hours") or [])),
                   default=0)
        dsun = d.get("sunTime") or {}
        d_rise = hhmm(dsun["sunrise"]) if "sunrise" in dsun else sunrise
        d_set = hhmm(dsun["sunset"]) if "sunset" in dsun else sunset
        forecast.append({
            "date": d.get("date", ""), "min": str(t.get("min", "")),
            "max": str(t.get("max", "")), "desc": label, "icon": glyph,
            "hex": colour, "rain": str(rain),
            "hours": day_hours(d, d_rise, d_set),
        })

    coords = loc.get("coordinates") or {}
    if "lat" in coords and "lng" in coords and \
            any(len(f["hours"]) < 24 for f in forecast):
        extra = open_meteo_hours(coords["lat"], coords["lng"])
        for f in forecast:
            if len(f["hours"]) < 24 and len(extra.get(f["date"], [])) == 24:
                f["hours"] = extra[f["date"]]

    # The next 24 hours as one flat strip: the rest of today, then tomorrow
    # until the count is full. Entries carry `tomorrow` so a reader can
    # label the midnight boundary.
    hourly = [dict(h, tomorrow=False) for h in forecast[0]["hours"]
              if h["hour"] >= now_clock.hour]
    if len(forecast) > 1:
        hourly += [dict(h, tomorrow=True) for h in forecast[1]["hours"]]
    hourly = hourly[:24]

    lines = "\n".join("%s   %s°/%s°   %s" % (f["date"], f["min"], f["max"], f["desc"])
                      for f in forecast[:5])
    tip = "%s\n%s — feels %s°C\n  Humidity %s%%    Wind %s km/h\n\n%s" % (
        area, desc, feels, humidity, wind, lines)

    json.dump({
        "text": "%s  %s°C" % (icon, temp), "tooltip": tip, "class": "weather",
        "icon": icon, "hex": hexv, "temp": str(temp), "feels": str(feels),
        "desc": desc, "area": area, "humidity": str(humidity), "wind": str(wind),
        "uv": "", "sunrise": sunrise, "sunset": sunset, "forecast": forecast,
        "hourly": hourly,
    }, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    sys.stderr.write("%s\n%s\n" % (sunset, sunrise))


if __name__ == "__main__":
    main()

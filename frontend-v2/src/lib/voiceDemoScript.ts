export type Lang = "en" | "hi" | "mr";

export interface DemoQA {
  id: string;
  // all keywords must appear (case-insensitive) in the transcript to match
  matchKeywords: string[];
  answer: string;
}

export const DEMO_QA: Record<Lang, DemoQA[]> = {
  en: [
    {
      id: "sightings_today",
      matchKeywords: ["tiger", "today"],
      answer:
        "There have been 118 confirmed tiger sightings today across all active camera stations.",
    },
    {
      id: "priority_alerts",
      matchKeywords: ["priority", "alert"],
      answer:
        "Target T-052 has not been sighted in the last three days. Earlier sightings placed it approaching a village boundary — that's the top priority right now.",
    },
    {
      id: "tigers_tracked",
      matchKeywords: ["how many tigers"],
      answer: "We are currently tracking 62 individual tigers across the reserve.",
    },
    {
      id: "village_proximity",
      matchKeywords: ["village"],
      answer:
        "Yes — target T-052 was last seen approaching the village of Sillari, within one kilometer of the buffer boundary.",
    },
    {
      id: "camera_stations",
      matchKeywords: ["camera", "active"],
      answer:
        "313 camera stations are currently active across the reserve, with an average uptime of 94 percent.",
    },
    {
      id: "station_status",
      matchKeywords: ["station", "status"],
      answer:
        "Camera station PTR_CAM_007 is currently online, with 91 percent uptime this month.",
    },
  ],
  hi: [
    {
      id: "sightings_today",
      matchKeywords: ["बाघ", "आज"],
      answer: "आज सभी सक्रिय कैमरा स्टेशनों पर 118 बाघों की पुष्टि हुई है।",
    },
    {
      id: "priority_alerts",
      matchKeywords: ["प्राथमिकता", "अलर्ट"],
      answer:
        "टारगेट टी-052 पिछले तीन दिनों से दिखाई नहीं दिया है। पहले की तस्वीरों में यह एक गांव की सीमा की ओर बढ़ता दिखा था — यह अभी सबसे बड़ी प्राथमिकता है।",
    },
    {
      id: "tigers_tracked",
      matchKeywords: ["कितने बाघ"],
      answer: "इस समय पूरे रिज़र्व में 62 बाघों को ट्रैक किया जा रहा है।",
    },
    {
      id: "village_proximity",
      matchKeywords: ["गांव"],
      answer:
        "हां — टारगेट टी-052 आखिरी बार सिल्लारी गांव की ओर बढ़ता देखा गया था, बफर सीमा से एक किलोमीटर के भीतर।",
    },
    {
      id: "camera_stations",
      matchKeywords: ["कैमरा", "सक्रिय"],
      answer: "रिज़र्व में इस समय 313 कैमरा स्टेशन सक्रिय हैं, औसत अपटाइम 94 प्रतिशत है।",
    },
    {
      id: "station_status",
      matchKeywords: ["स्टेशन", "स्थिति"],
      answer: "कैमरा स्टेशन पीटीआर कैम 007 इस समय ऑनलाइन है, इस महीने 91 प्रतिशत अपटाइम के साथ।",
    },
  ],
  mr: [
    {
      id: "sightings_today",
      matchKeywords: ["वाघ", "आज"],
      answer: "आज सर्व सक्रिय कॅमेरा स्टेशन्सवर 118 वाघांची नोंद झाली आहे.",
    },
    {
      id: "priority_alerts",
      matchKeywords: ["प्राधान्य", "अलर्ट"],
      answer:
        "टार्गेट टी-052 गेल्या तीन दिवसांपासून दिसलेला नाही. आधीच्या नोंदींमध्ये तो गावाच्या सीमेकडे जाताना दिसला होता — सध्या हीच सर्वात मोठी प्राधान्याची बाब आहे.",
    },
    {
      id: "tigers_tracked",
      matchKeywords: ["किती वाघ"],
      answer: "सध्या संपूर्ण राखीव क्षेत्रात 62 वाघांचा मागोवा घेतला जात आहे.",
    },
    {
      id: "village_proximity",
      matchKeywords: ["गाव"],
      answer:
        "होय — टार्गेट टी-052 शेवटचा सिल्लारी गावाच्या दिशेने जाताना दिसला होता, बफर सीमेपासून एक किलोमीटरच्या आत.",
    },
    {
      id: "camera_stations",
      matchKeywords: ["कॅमेरा", "सक्रिय"],
      answer: "राखीव क्षेत्रात सध्या 313 कॅमेरा स्टेशन्स सक्रिय आहेत, सरासरी अपटाइम 94 टक्के आहे.",
    },
    {
      id: "station_status",
      matchKeywords: ["स्टेशन", "स्थिती"],
      answer: "कॅमेरा स्टेशन पीटीआर कॅम 007 सध्या ऑनलाइन आहे, या महिन्यात 91 टक्के अपटाइमसह.",
    },
  ],
};

export const FALLBACK_ANSWER: Record<Lang, string> = {
  en: "I don't have an answer for that in this demo yet — try asking about today's tiger sightings or priority alerts.",
  hi: "इस डेमो में इसका उत्तर अभी उपलब्ध नहीं है — कृपया आज के बाघ दिखने या प्राथमिकता अलर्ट के बारे में पूछें।",
  mr: "या डेमोमध्ये याचे उत्तर अजून उपलब्ध नाही — कृपया आजच्या वाघांच्या नोंदी किंवा प्राधान्य अलर्टबद्दल विचारा.",
};

export function matchDemoAnswer(transcript: string, lang: Lang): string {
  const lower = transcript.toLowerCase();
  const table = DEMO_QA[lang];
  const hit = table.find((qa) =>
    qa.matchKeywords.every((kw) => lower.includes(kw.toLowerCase()))
  );
  return hit ? hit.answer : FALLBACK_ANSWER[lang];
}

// Decides which language a transcript is actually in by checking which
// language's keyword table it matches. `preferred`, when given (e.g. Scribe's
// own detected language_code), is tried first; otherwise all candidates are
// checked in order — content match wins over any upstream language hint.
export function detectLangFromTranscript(
  transcript: string,
  candidates: Lang[],
  preferred?: Lang | null
): Lang | null {
  const lower = transcript.toLowerCase();
  const order = preferred && candidates.includes(preferred)
    ? [preferred, ...candidates.filter((c) => c !== preferred)]
    : candidates;
  for (const lang of order) {
    const table = DEMO_QA[lang];
    const matches = table.some((qa) =>
      qa.matchKeywords.every((kw) => lower.includes(kw.toLowerCase()))
    );
    if (matches) return lang;
  }
  return null;
}

// ElevenLabs Scribe returns ISO 639-3 codes (e.g. "eng", "hin", "mar"), not
// the ISO 639-1 codes ("en", "hi", "mr") used elsewhere in this app.
const SCRIBE_LANG_MAP: Record<string, Lang> = {
  en: "en",
  eng: "en",
  hi: "hi",
  hin: "hi",
  mr: "mr",
  mar: "mr",
};

export function normalizeScribeLang(code: string | null | undefined): Lang | null {
  if (!code) return null;
  return SCRIBE_LANG_MAP[code.toLowerCase()] ?? null;
}

export function isKnownLang(code: string | null | undefined): code is Lang {
  return code === "en" || code === "hi" || code === "mr";
}

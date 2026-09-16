import { NextRequest, NextResponse } from "next/server";
import Groq from "groq-sdk";
import { GoogleGenAI, type Content } from "@google/genai";
import { ASSISTANT_TOOLS, ASSISTANT_TOOLS_OPENAI, runAssistantTool } from "@/lib/assistantTools";
import type { Lang } from "@/lib/voiceDemoScript";

const GROQ_MODEL = "openai/gpt-oss-120b";
const GEMINI_MODEL = "gemini-3.6-flash";
const MAX_TOOL_ROUNDS = 4;

const LANG_NAMES: Record<Lang, string> = {
  en: "English",
  hi: "Hindi",
  mr: "Marathi",
};

function systemInstruction(lang: Lang) {
  return `You are the TYGRIS field assistant, a voice/chat assistant for forest rangers monitoring a tiger reserve.
Answer the ranger's question using ONLY real data fetched via the available tools — never guess or invent numbers, tiger IDs, or station names.
If a question needs data (tiger counts, alerts, station status, tiger location, villages, etc.), call the relevant tool(s) before answering.
Keep answers short, spoken-style, and to the point — 1-3 sentences, suitable for a ranger to hear read aloud in the field.
Respond in ${LANG_NAMES[lang]}, regardless of what language the tools return data in.
If the tools don't have the information needed to answer, say so plainly instead of making something up.`;
}

export interface AssistantMessage {
  role: "user" | "assistant";
  text: string;
}

async function answerWithGroq(message: string, lang: Lang, history: AssistantMessage[], apiKey: string): Promise<string> {
  const groq = new Groq({ apiKey });

  const messages: Groq.Chat.Completions.ChatCompletionMessageParam[] = [
    { role: "system", content: systemInstruction(lang) },
    ...history.map((m) => ({
      role: (m.role === "assistant" ? "assistant" : "user") as "assistant" | "user",
      content: m.text,
    })),
    { role: "user", content: message },
  ];

  for (let round = 0; round < MAX_TOOL_ROUNDS; round++) {
    const completion = await groq.chat.completions.create({
      model: GROQ_MODEL,
      messages,
      tools: ASSISTANT_TOOLS_OPENAI,
      tool_choice: "auto",
    });

    const choice = completion.choices[0].message;
    const toolCalls = choice.tool_calls ?? [];

    if (toolCalls.length === 0) {
      const answer = choice.content?.trim();
      if (!answer) throw new Error("Assistant returned an empty response.");
      return answer;
    }

    messages.push(choice);
    for (const call of toolCalls) {
      const args = call.function.arguments ? JSON.parse(call.function.arguments) : {};
      const result = await runAssistantTool(call.function.name, args);
      messages.push({ role: "tool", tool_call_id: call.id, content: JSON.stringify(result) });
    }
  }

  throw new Error("Assistant couldn't settle on an answer after several tool calls.");
}

async function answerWithGemini(message: string, lang: Lang, history: AssistantMessage[], apiKey: string): Promise<string> {
  const ai = new GoogleGenAI({ apiKey });

  const contents: Content[] = [
    ...history.map((m) => ({
      role: m.role === "assistant" ? "model" : "user",
      parts: [{ text: m.text }],
    })),
    { role: "user", parts: [{ text: message }] },
  ];

  for (let round = 0; round < MAX_TOOL_ROUNDS; round++) {
    const response = await ai.models.generateContent({
      model: GEMINI_MODEL,
      contents,
      config: {
        systemInstruction: systemInstruction(lang),
        tools: [{ functionDeclarations: ASSISTANT_TOOLS }],
      },
    });

    const calls = response.functionCalls ?? [];
    if (calls.length === 0) {
      const answer = response.text?.trim();
      if (!answer) throw new Error("Assistant returned an empty response.");
      return answer;
    }

    const modelContent = response.candidates?.[0]?.content;
    if (modelContent) contents.push(modelContent);

    const responseParts = await Promise.all(
      calls.map(async (call) => {
        const result = await runAssistantTool(call.name ?? "", (call.args as Record<string, unknown>) ?? {});
        return { functionResponse: { name: call.name, response: { result } } };
      })
    );
    contents.push({ role: "user", parts: responseParts });
  }

  throw new Error("Assistant couldn't settle on an answer after several tool calls.");
}

export async function POST(req: NextRequest) {
  const groqKey = process.env.GROQ_API_KEY;
  const geminiKey = process.env.GEMINI_API_KEY;
  if (!groqKey && !geminiKey) {
    return NextResponse.json(
      { error: "Neither GROQ_API_KEY nor GEMINI_API_KEY is configured on the server." },
      { status: 500 }
    );
  }

  const body = await req.json();
  const message: string = body.message ?? "";
  const lang: Lang = body.lang === "hi" || body.lang === "mr" ? body.lang : "en";
  const history: AssistantMessage[] = Array.isArray(body.history) ? body.history : [];

  if (!message.trim()) {
    return NextResponse.json({ error: "message is required" }, { status: 400 });
  }

  // Groq (gpt-oss-120b) is fast and has a much higher free-tier request
  // ceiling than Gemini's, but its Marathi comprehension tested unreliable
  // (misread valid Marathi questions as unclear). Gemini tested fine on
  // Marathi, so try it first for mr; Groq handles en/hi. Whichever runs
  // first, the other provider is tried if it fails (rate limit, outage).
  const groq = groqKey ? () => answerWithGroq(message, lang, history, groqKey) : null;
  const gemini = geminiKey ? () => answerWithGemini(message, lang, history, geminiKey) : null;
  const providers = (lang === "mr" ? [gemini, groq] : [groq, gemini]).filter((p) => p !== null);

  let lastError: unknown;
  for (const provider of providers) {
    try {
      const answer = stripMarkdown(await provider());
      return NextResponse.json({ answer, lang });
    } catch (err) {
      console.error("[assistant] provider failed:", err);
      lastError = err;
    }
  }

  return NextResponse.json(
    { error: lastError instanceof Error ? lastError.message : "Assistant request failed." },
    { status: 500 }
  );
}

// Answers are shown as plain text and read aloud, so drop markdown emphasis/headers/bullets.
function stripMarkdown(text: string) {
  return text
    .replace(/\*\*(.+?)\*\*/g, "$1")
    .replace(/__(.+?)__/g, "$1")
    .replace(/`([^`]+)`/g, "$1")
    .replace(/^#{1,6}\s+/gm, "")
    .replace(/^\s*[-*]\s+/gm, "")
    .trim();
}

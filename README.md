<p align="center">
  <img src="https://img.shields.io/badge/Salesforce-00A1E0?style=for-the-badge&logo=salesforce&logoColor=white" />
  <img src="https://img.shields.io/badge/Lightning_Web_Components-00A1E0?style=for-the-badge&logo=salesforce&logoColor=white" />
  <img src="https://img.shields.io/badge/OpenAI-412991?style=for-the-badge&logo=openai&logoColor=white" />
  <img src="https://img.shields.io/badge/Anthropic-Claude-6366f1?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Apex-FF6B35?style=for-the-badge&logo=salesforce&logoColor=white" />
</p>

<h1 align="center">🎙️ Voice to CRM</h1>

<p align="center">
  <strong>Talk to Salesforce. Let AI do the typing.</strong><br/>
  A Siri-style floating voice widget for Opportunity record pages that turns natural speech into Salesforce actions.
</p>

<p align="center">
  <em>Speak for 30 seconds → AI parses 7 actions → One tap confirms → Salesforce updated ✅</em>
</p>

---

## ✨ What It Does

> 🗣️ *"Just had a great call with Sarah Chen at Acme. She's the VP of Ops. They're moving forward but need legal review. Push close date to April 30. Next step is send the SOW by Friday. Add their CTO Mike as a stakeholder."*

**Voice to CRM** listens, understands, and executes:

| # | Action | Detail |
|---|--------|--------|
| ⚡ | Update Stage | Negotiation → Legal Review |
| 📅 | Update Close Date | Mar 28 → April 30, 2026 |
| 📞 | Log Activity | Call with Sarah Chen — discussed legal review |
| 👤 | Create Contact | Mike — CTO at Acme Corp |
| 🔗 | Add Contact Role | Mike → Stakeholder |
| 📋 | Create Task | Send SOW — Due: Friday |
| 📋 | Create Task | Follow up legal review — Due: Apr 15 |

**All from one voice input. Zero clicks. Zero typing.**

---

## 🎨 The Widget

The component lives as a **small 56px floating orb** in the bottom-left corner of any Opportunity record page — like a Siri button.

### 💜 Collapsed State
- Glowing purple orb with gentle Siri wave animation
- Pulsing glow effect — always subtly alive
- Click to expand

### 🟣 Expanded States

| State | What Happens |
|-------|-------------|
| 🎙️ **Idle** | Large Siri orb + mic button — *"Tap to update with voice"* |
| 🔴 **Listening** | Red recording button, live timer, amplified wave animation |
| ⌨️ **Transcribing** | Typewriter effect reveals your words in real-time |
| 🔮 **Parsing** | Shimmer loading bar — *"AI parsing..."* |
| ✅ **Confirming** | Action cards appear — review each one, tap *"Confirm All"* |
| 🚀 **Updating** | Checkmarks cascade across action cards |
| 🎉 **Done** | Success animation — *"7 actions completed in 2.4s"* |

Auto-collapses back to the orb after completion.

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────┐
│                  BROWSER                         │
│                                                  │
│  🎙️ Web Speech API ──→ Transcript (text)        │
│                              │                   │
│  ┌───────────────────────────▼────────────────┐  │
│  │         voiceToCrm (LWC)                   │  │
│  │  • Siri canvas animation                   │  │
│  │  • State machine (7 states)                │  │
│  │  • Action card UI                          │  │
│  └───────────────────┬───────────────────────┘  │
│                      │ Apex callout              │
└──────────────────────┼───────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────┐
│              SALESFORCE ORG                        │
│                                                    │
│  VoiceToCrmController.cls                          │
│  ├── parseVoiceInput()                             │
│  │   ├── Reads picklist values (Stage, Roles)      │
│  │   ├── Builds AI prompt with org context         │
│  │   └── Calls ClaudeApiService                    │
│  └── executeActions()                              │
│      ├── Update Opportunity fields                 │
│      ├── Create Contact + Contact Role             │
│      ├── Log Activity (completed Task)             │
│      └── Create Tasks with due dates               │
│                                                    │
│  ClaudeApiService.cls                              │
│  ├── 🤖 OpenAI (gpt-4o-mini)                      │
│  └── 🧠 Claude (claude-3.5-sonnet)                │
│       ↕ switchable via Custom Metadata             │
└────────────────────────────────────────────────────┘
```

---

## 🔌 Dual AI Provider Support

Switch between **OpenAI** and **Claude** with zero code changes — just a picklist toggle in Setup.

| Setting | OpenAI | Claude |
|---------|--------|--------|
| 🏷️ Provider | `OpenAI` | `Claude` |
| 🔑 Key format | `sk-...` | `sk-ant-...` |
| 🤖 Model | `gpt-4o-mini` | `claude-3.5-sonnet` |
| 💰 Cost | ~$0.001/request | ~$0.003/request |
| ⚡ Speed | Fast | Fast |

**Switch anytime:** Setup → Custom Metadata Types → Voice CRM Settings → Default → Edit `AI Provider`

---

## 📁 Project Structure

```
voice-to-crm/
├── force-app/main/default/
│   ├── lwc/voiceToCrm/
│   │   ├── 🎨 voiceToCrm.html          # Floating widget markup
│   │   ├── ⚙️ voiceToCrm.js            # State machine + voice capture + Siri animation
│   │   ├── 💅 voiceToCrm.css           # Dark glassmorphic UI + animations
│   │   └── 📦 voiceToCrm.js-meta.xml   # Exposed on Opportunity record pages
│   │
│   ├── classes/
│   │   ├── 🧠 VoiceToCrmController.cls      # AI parsing + DML execution
│   │   ├── 🔌 ClaudeApiService.cls           # Dual provider (OpenAI + Claude)
│   │   ├── 🧪 VoiceToCrmControllerTest.cls   # 6 test methods + API mock
│   │   └── 📄 *.cls-meta.xml
│   │
│   ├── objects/Voice_CRM_Settings__mdt/
│   │   ├── 🏷️ AI_Provider__c             # Picklist: OpenAI / Claude
│   │   ├── 🔑 Claude_API_Key__c          # Anthropic API key
│   │   └── 🔑 OpenAI_API_Key__c          # OpenAI API key
│   │
│   ├── customMetadata/
│   │   └── 📋 Voice_CRM_Settings.Default  # Default config record
│   │
│   └── remoteSiteSettings/
│       ├── 🌐 Claude_API                  # api.anthropic.com
│       └── 🌐 OpenAI_API                  # api.openai.com
│
├── config/
│   └── project-scratch-def.json
└── sfdx-project.json
```

---

## 🚀 Installation & Setup

### Prerequisites

- ✅ Salesforce org (Developer, Sandbox, or Scratch)
- ✅ Salesforce CLI installed (`sf --version`)
- ✅ API key from [OpenAI](https://platform.openai.com/api-keys) or [Anthropic](https://console.anthropic.com)
- ✅ Chrome browser (for Web Speech API)

### Step 1: Clone & Deploy

```bash
# Clone the repo
git clone <your-repo-url>
cd voice-to-crm

# Deploy to your org
sf project deploy start --source-dir force-app --target-org YourOrgAlias
```

### Step 2: Configure API Key 🔑

1. Go to **Setup** → search **"Custom Metadata Types"**
2. Click **Voice CRM Settings** → **Manage Records**
3. Click **Default** → **Edit**
4. Set your preferred provider:

| Field | Value |
|-------|-------|
| **AI Provider** | `OpenAI` (recommended) or `Claude` |
| **OpenAI API Key** | `sk-proj-...` (from platform.openai.com) |
| **Claude API Key** | `sk-ant-api03-...` (from console.anthropic.com) |

5. Click **Save** ✅

### Step 3: Add to Opportunity Page 🎯

1. Open any **Opportunity** record
2. Click ⚙️ **Setup** → **Edit Page**
3. In Lightning App Builder, drag **"Voice to CRM"** anywhere on the page
4. Click **Save** → **Activate**
5. The floating orb appears in the **bottom-left corner** 💜

---

## 🎯 How to Use

```
1️⃣  Click the purple orb → Panel opens with mic button
2️⃣  Tap the mic → Start speaking naturally
3️⃣  Tap stop → Watch your words appear (typewriter effect)
4️⃣  AI parses → Action cards appear with what will be updated
5️⃣  Review → Tap "Confirm All" or edit individual actions
6️⃣  Done → Salesforce updated, page refreshes ✨
```

### 💡 Tips for Best Results

- 🗣️ **Speak naturally** — say it like you'd tell a colleague
- 📅 **Be specific with dates** — "April 30" works better than "next month"
- 👤 **Name contacts clearly** — "Add Mike Johnson, he's the CTO"
- 📋 **Mention next steps** — "Next step is send the proposal by Friday"
- 🏷️ **Use stage names** — "Move to Negotiation" or "Close this deal"

---

## 🧪 Testing

```bash
# Run Apex tests
sf apex run test --class-names VoiceToCrmControllerTest --result-format human --target-org YourOrgAlias
```

### Test Coverage

| Test Method | What It Tests |
|-------------|--------------|
| `testExecuteActions_UpdateOpportunity` | ⚡ Stage + close date updates |
| `testExecuteActions_CreateTask` | 📋 Task creation with due dates |
| `testExecuteActions_LogActivity` | 📞 Completed activity logging |
| `testExecuteActions_CreateContact` | 👤 Contact + account association |
| `testExecuteActions_MultipleActions` | 🔄 Batch processing (3 actions) |
| `testParseVoiceInput` | 🤖 AI API callout with mock |

---

## ⚡ Supported Actions

| Action | Icon | What It Does |
|--------|------|-------------|
| **Update Opportunity** | ⚡ | Stage, Close Date, Probability, Next Step |
| **Log Activity** | 📞 | Creates a completed Task (Call/Meeting) |
| **Create Contact** | 👤 | New Contact linked to the Account |
| **Add Contact Role** | 🔗 | Links Contact to the Opportunity with a Role |
| **Create Task** | 📋 | Future task with subject, due date, description |

---

## 🔒 Security

- 🔐 API keys stored in **Custom Metadata** (not in code)
- 🛡️ All Apex classes use `with sharing` (respects org permissions)
- 🌐 Remote Site Settings restrict callouts to approved endpoints only
- ✅ No data leaves Salesforce except the voice transcript sent to the AI provider
- 🔑 Keys are **subscriber-controlled** — each org manages their own

---

## 🛠️ Troubleshooting

| Issue | Solution |
|-------|----------|
| 🎙️ Mic not working | Use **Chrome** — Safari/Firefox don't support Web Speech API |
| 🔴 API error 401 | Check your API key in Custom Metadata |
| 🔴 API error 400 | Verify credits/billing on your AI provider account |
| 👻 Actions invisible | Redeploy latest CSS (opacity fix applied) |
| 🔇 No speech detected | Check browser mic permissions (allow for your SF domain) |
| ⏱️ Timeout | Increase `setTimeout` in `ClaudeApiService.cls` (default: 60s) |

---

## 🗺️ Roadmap

- [ ] 🌍 Multi-language support (Spanish, French, etc.)
- [ ] 📱 Salesforce Mobile optimization
- [ ] 🔄 Gong integration — auto-parse call recordings
- [ ] ✏️ Inline editing of individual action cards
- [ ] 📊 Voice activity analytics dashboard
- [ ] 🤖 Support for more AI providers (Gemini, Mistral)
- [ ] 🏠 Extend to Account, Lead, and Case objects

---

## 📄 License

MIT License — build, modify, distribute, and sell freely.

---

<p align="center">
  <strong>🎙️ Voice to CRM</strong><br/>
  <em>Stop typing. Start talking.</em><br/><br/>
  Built with 💜 by <strong>Rushika P.</strong>
</p>

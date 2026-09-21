# Textractor Pro — STEM OCR Roadmap

**Vision:** A premium tier for scientists, engineers, and researchers who need advanced OCR for mathematical notation, chemical formulas, handwriting, and technical diagrams — all on-device, privacy-first.

---

## 🎯 Positioning

| Textractor (Core) | Textractor Pro |
|-------------------|----------------|
| Free / $12.99 one-time | $4.99/mo or $49/yr subscription |
| General text, code, docs | STEM, handwriting, diagrams |
| Vision framework only | Vision + custom CoreML models |
| 26 languages | 50+ languages + math/chem notation |
| Text output | Structured output (LaTeX, MathML, SMILES) |

---

## 🗓️ Phase 1: Foundation (Months 1-2)

### Models to Train/Integrate
| Model | Base | Training Data | Output |
|-------|------|---------------|--------|
| **MathOCR** | TrOCR-base | MathWriting (1M samples) + synthetic LaTeX | LaTeX / MathML |
| **ChemOCR** | TrOCR-base | PubChem + synthetic SMILES→image | SMILES / ChemDraw |
| **HandwritingOCR** | TrOCR-base | EMNIST + synthetic cursive (50 langs) | Unicode text |
| **LayoutOCR** | LayoutLMv3 | PubLayNet + synthetic technical docs | Structured JSON (blocks, tables, figures) |

### Infrastructure
- [ ] **MLModelManager** — multi-model loading, caching, memory management
- [ ] **STEMOCREngine** — ensemble router (Vision → custom models → post-process)
- [ ] **CoreML quantization** — INT8/INT4 for <50MB total model size
- [ ] **Model versioning** — semantic versioning, auto-update via app bundle

---

## 🗓️ Phase 2: STEM Features (Months 3-4)

### Mathematical Notation
- [ ] **LaTeX output** — `$\int_0^\infty e^{-x^2} dx = \frac{\sqrt{\pi}}{2}$`
- [ ] **MathML output** — for web/accessibility
- [ ] **Visual layout preservation** — fractions, matrices, integrals as positioned elements
- [ ] **Symbol detection** — Greek, operators, arrows, delimiters, accents
- [ ] **Inline vs display math** — auto-detect $...$ vs $$...$$

### Chemical Formulas
- [ ] **SMILES output** — `CC(=O)OC1=CC=CC=C1C(=O)O` (aspirin)
- [ ] **Sub/superscript preservation** — H₂O, CO₂, Ca²⁺, SO₄²⁻
- [ ] **Reaction arrows** — →, ⇌, ⇄ with conditions
- [ ] **Ring structures** — benzene, cyclohexane detection

### Handwriting
- [ ] **Print + cursive** — EMNIST + synthetic cursive (50 languages)
- [ ] **Mixed print/handwriting** — e.g., annotated code, lab notes
- [ ] **Margin notes** — detect and associate with main text

### Diagrams/Charts
- [ ] **Table extraction** → CSV/Markdown (extend existing)
- [ ] **Flowchart → Mermaid.js** — boxes, arrows, decision diamonds
- [ ] **Plot digitization** — axes, data points, trend lines
- [ ] **Circuit diagrams** → SPICE netlist (stretch)

---

## 🗓️ Phase 3: Structured Output (Month 5)

### Export Formats
| Format | Use Case |
|--------|----------|
| **LaTeX** | Papers, Overleaf |
| **MathML** | Web, accessibility |
| **SMILES/SDF** | ChemDraw, RDKit |
| **JSON-LD** | Knowledge graphs |
| **Notion/Obsidian** | Direct plugin export |
| **Jupyter** | `.ipynb` with markdown + code cells |

### Smart Structuring
- [ ] **Section detection** — abstract, methods, results, references
- [ ] **Figure/table caption association**
- [ ] **Reference extraction** — DOIs, arXiv IDs
- [ ] **Code block detection** — language classification + syntax highlight

---

## 🗓️ Phase 4: Pro UX (Month 6)

### Capture Modes
- [ ] **STEM Region** — auto-routes to Math/Chem/Handwriting models
- [ ] **Whiteboard mode** — multi-capture stitching for large boards
- [ ] **Document scan** — multi-page PDF with OCR + structure
- [ ] **Video frame extraction** — lecture capture → key frames

### Integration
- [ ] **Overleaf sync** — push LaTeX directly
- [ ] **Obsidian/Notion plugin** — bidirectional
- [ ] **Zotero/Mendeley** — citation extraction
- [ ] **GitHub/GitLab** — code blocks → gists

### Collaboration
- [ ] **Shared workspaces** — team STEM captures
- [ ] **Annotations** — highlight, comment on captures
- [ ] **Version history** — diff captures over time

---

## 💰 Business Model

| Tier | Price | Includes |
|------|-------|----------|
| **Textractor** | $12.99 one-time | Core OCR, code mode, translation, history |
| **Textractor Pro** | $4.99/mo / $49/yr | All Pro models, structured export, integrations |
| **Team** | $12/user/mo | Shared workspaces, admin, SSO |

---

## 🔒 Privacy (Same as Core)

- ✅ 100% on-device
- ✅ No telemetry on Pro models
- ✅ Models bundled in app (no download)
- ✅ Opt-in analytics only

---

## 📦 Distribution

- **Mac App Store** — In-App Purchase for Pro subscription
- **Direct** — License key validation (Paddle/LemonSqueezy)
- **Setapp** — Revenue share

---

## 📊 Success Metrics

| Metric | Target |
|--------|--------|
| Pro conversion | 5% of core users |
| Monthly churn | <5% |
| Model accuracy (math) | >95% symbol accuracy |
| Model size | <100MB total |
| OCR latency (Pro) | <2s on M1 |

---

*This roadmap is independent of core Textractor. Core remains free/one-time, privacy-first, general-purpose. Pro is opt-in for STEM power users.*
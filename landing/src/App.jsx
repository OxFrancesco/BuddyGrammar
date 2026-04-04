import './App.css'

const features = [
  { icon: '⌨', title: 'Global Hotkeys', desc: 'Assign a unique keyboard shortcut to each personality and trigger rewrites from any app.' },
  { icon: '🔑', title: 'Keychain Storage', desc: 'Your OpenRouter API key is stored in the macOS Keychain — never written to disk in plain text.' },
  { icon: '📋', title: 'Replace or Copy', desc: 'Choose to replace the selection in place or copy the rewritten text to the clipboard.' },
  { icon: '🧩', title: 'Custom Personalities', desc: 'Start from templates like Formal, Email, and Twitter Post, then customize the label, shortcut, and system prompt.' },
  { icon: '♿', title: 'Accessibility-First', desc: 'Uses macOS Accessibility APIs to capture and replace text, with a clipboard fallback.' },
  { icon: '▪', title: 'Lives in Menu Bar', desc: 'A lightweight status item shows live rewrite progress — no windows to manage.' },
]

const steps = [
  { title: 'Select text anywhere', desc: 'Highlight text in any application — a browser, Notes, Slack, your editor.' },
  { title: 'Press ⌘⇧1', desc: 'The default Standard personality fires and BuddyGrammar grabs the selection.' },
  { title: 'AI rewrites it', desc: 'The text is sent to OpenRouter (gpt-5.4-nano) and rewritten in seconds.' },
  { title: 'Fixed text appears', desc: 'The corrected text replaces your selection — or lands in the clipboard.' },
]

function App() {
  return (
    <>
      <div className="bg-layer">
        <img src="/bg.svg" alt="" />
      </div>

      {/* Nav */}
      <nav>
        <div className="logo">
          <img className="logo-icon" src="/logo.png" alt="" />
          BuddyGrammar
        </div>
        <div className="nav-links">
          <a href="#features">Features</a>
          <a href="#how">How it works</a>
          <a
            href="https://github.com/oxfrancesco/buddygrammar"
            className="neo-btn neo-btn-secondary"
            style={{ padding: '8px 16px', fontSize: 12 }}
          >
            GitHub
          </a>
        </div>
      </nav>

      {/* Hero */}
      <section className="hero">
        <div className="hero-mark">
          <img className="hero-logo" src="/logo.png" alt="BuddyGrammar logo" />
        </div>
        <h1>
          Fix your text with <em>one shortcut</em>
        </h1>
        <p>
          A native macOS menu bar utility that grabs selected text, rewrites it
          with AI personalities, and pastes it back instantly.
        </p>
        <div className="hero-actions">
          <a
            href="https://github.com/oxfrancesco/buddygrammar/releases"
            className="neo-btn neo-btn-primary"
          >
            ⬇ Download
          </a>
          <a
            href="https://github.com/oxfrancesco/buddygrammar"
            className="neo-btn neo-btn-secondary"
          >
            View Source
          </a>
        </div>

      </section>

      {/* Demo */}
      <section className="demo">
        <div className="demo-window neo-card">
          <div className="demo-titlebar">
            <div className="demo-dot r" />
            <div className="demo-dot y" />
            <div className="demo-dot g" />
          </div>
          <div className="demo-body">
            <div className="demo-before">
              "i dont no how to right this sentance proper"
            </div>
            <span className="demo-arrow">⟱ ⌘⇧1</span>
            <div className="demo-after">
              "I don't know how to write this sentence properly."
            </div>
          </div>
        </div>
      </section>

      {/* Features */}
      <section className="features" id="features">
        <h2>Features</h2>
        <div className="features-grid">
          {features.map((f) => (
            <div className="feature-card neo-card" key={f.title}>
              <div className="feature-icon">{f.icon}</div>
              <h3>{f.title}</h3>
              <p>{f.desc}</p>
            </div>
          ))}
        </div>
      </section>

      {/* How it works */}
      <section className="steps" id="how">
        <h2>How it works</h2>
        {steps.map((s, i) => (
          <div className="step-row" key={i}>
            <div className="step-num">{i + 1}</div>
            <div className="step-text">
              <h3>{s.title}</h3>
              <p>{s.desc}</p>
            </div>
          </div>
        ))}
      </section>

      {/* CTA */}
      <section className="cta">
        <div className="cta-card neo-card">
          <h2>Ready to write better?</h2>
          <p>
            BuddyGrammar is free and open source. Download it, add your
            OpenRouter key, and start fixing text in seconds.
          </p>
          <a
            href="https://github.com/oxfrancesco/buddygrammar/releases"
            className="neo-btn neo-btn-primary"
          >
            ⬇ Download BuddyGrammar
          </a>
        </div>
      </section>

      <footer>
        Built by{' '}
        <a href="https://github.com/oxfrancesco">Francesco</a> ·{' '}
        <a href="https://github.com/oxfrancesco/buddygrammar">GitHub</a> ·
        macOS 15+
      </footer>
    </>
  )
}

export default App

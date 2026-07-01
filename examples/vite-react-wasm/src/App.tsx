import { ChangeEvent, useEffect, useRef, useState } from "react";
import { ChevronDown, ChevronUp } from "lucide-react";
import { loadCapriceWasm } from "./capriceWasm";

type InputMode = "text" | "file";
type Theme = "light" | "dark";
type LineResult = {
  lineNumber: number;
  formula: string;
  result: string;
  isError: boolean;
};

const SAMPLE = `(a = 123456)

(not (b = a))

(not (b = a)) ^ (d = c)

(a = 123456) ^ (b = 123456)

(a = 123456) ^ (not (b = 123456)) ^ (c = 123456)

(a = 123456) ^ (b = 123456) ^ (c = 123456)`;

function Icon({
  children,
  size = 18,
}: {
  children: React.ReactNode;
  size?: number;
}) {
  return (
    <svg
      aria-hidden="true"
      className="icon"
      fill="none"
      height={size}
      viewBox="0 0 24 24"
      width={size}
    >
      {children}
    </svg>
  );
}

export default function App() {
  const [mode, setMode] = useState<InputMode>("text");
  const [theme, setTheme] = useState<Theme>(() => {
    const saved = localStorage.getItem("blue3-theme");
    if (saved === "light" || saved === "dark") return saved;
    return matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  });
  const [text, setText] = useState(SAMPLE);
  const [fileName, setFileName] = useState("");
  const [status, setStatus] = useState("Loading WebAssembly runtime…");
  const [isReady, setIsReady] = useState(false);
  const [results, setResults] = useState<LineResult[]>([]);
  const fileInput = useRef<HTMLInputElement>(null);

  useEffect(() => {
    document.documentElement.classList.toggle("dark", theme === "dark");
    localStorage.setItem("blue3-theme", theme);
  }, [theme]);

  useEffect(() => {
    loadCapriceWasm()
      .then(() => {
        setIsReady(true);
        setStatus("Blue3 runtime ready");
      })
      .catch((error: unknown) => {
        const message = error instanceof Error ? error.message : String(error);
        setStatus(`Runtime unavailable: ${message}`);
      });
  }, []);

  async function selectFile(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) return;
    setFileName(file.name);
    setText(await file.text());
  }

  async function solveInput() {
    const inputs = text
      .split(/\r?\n/)
      .map((input) => input.trim())
      .filter((input) => input && !input.startsWith("#"))
      .map((input, index) => ({ input, lineNumber: index + 1 }));

    if (inputs.length === 0) {
      setStatus("Input error: enter a constraint formula");
      setResults([]);
      return;
    }
    setStatus("Running Blue3 pipeline…");
    try {
      const caprice = await loadCapriceWasm();
      const nextResults = inputs.map(({ input, lineNumber }) => {
        const result = caprice.solveInput(input);
        return {
          lineNumber,
          formula: input,
          result: result.startsWith("Error:")
            ? result.slice("Error:".length).trim()
            : result,
          isError: result.startsWith("Error:"),
        };
      });
      const errorCount = nextResults.filter(({ isError }) => isError).length;
      setResults(nextResults);
      setStatus(
        `Solved ${nextResults.length} line${nextResults.length === 1 ? "" : "s"}`
        + (errorCount ? ` · ${errorCount} input error${errorCount === 1 ? "" : "s"}` : ""),
      );
    } catch (error: unknown) {
      setStatus(
        `Runtime error: ${error instanceof Error ? error.message : String(error)}`,
      );
      setResults([]);
    }
  }

  return (
    <div className="app-shell">
      <header className="site-header">
        <a className="brand" href="#" aria-label="Blue3 home">
          <span className="brand-mark">B3</span>
          <span>
            <strong>Blue3</strong>
            <small>Caprice Research Workbench</small>
          </span>
        </a>
        <button
          className="icon-button"
          type="button"
          aria-label={`Switch to ${theme === "dark" ? "light" : "dark"} mode`}
          onClick={() => setTheme(theme === "dark" ? "light" : "dark")}
        >
          {theme === "dark" ? (
            <Icon>
              <circle cx="12" cy="12" r="4" stroke="currentColor" strokeWidth="2" />
              <path d="M12 2v2m0 16v2M4.93 4.93l1.42 1.42m11.3 11.3 1.42 1.42M2 12h2m16 0h2M4.93 19.07l1.42-1.42m11.3-11.3 1.42-1.42" stroke="currentColor" strokeLinecap="round" strokeWidth="2" />
            </Icon>
          ) : (
            <Icon>
              <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79Z" stroke="currentColor" strokeLinejoin="round" strokeWidth="2" />
            </Icon>
          )}
        </button>
      </header>

      <main>
        <section className="hero">
          <div className="eyebrow"><span /> Browser-based SMT research tool</div>
          <h1>Explore constraints with <em>Blue3.</em></h1>
          <p>
            A research interface for the lightweight SMT solver inside Caprice.
            Blue3 sits between Caprice’s concolic evaluator and its solver
            backends, handling fast integer-difference logic cases in-process
            and deferring unsupported formulas to a general-purpose solver.
          </p>
          <p className="constraint-description">
            In plain programming terms, Blue3 can check conditions that compare
            integer variables with each other or with fixed offsets—for example,
            whether <code>x &lt;= 10</code>, <code>x &lt; y + 3</code>, or several
            such checks joined with AND, OR, and NOT can all be true at once.
            This is the original integer difference logic (IDL) concept: integer
            relationships based on differences and constants, rather than
            general arithmetic such as multiplying two variables.
          </p>
          <div className="pipeline" aria-label="Caprice pipeline">
            <span>Caprice source</span><b>→</b><span>Type checker</span><b>→</b>
            <span>Concolic evaluation</span><b>→</b><span className="active">Blue3</span>
          </div>
        </section>

        <section className="workspace">
          <div className="card">
            <div className="card-header">
              <div>
                <h2>Solver input</h2>
                <p>Prepare source text for the Caprice analysis pipeline.</p>
              </div>
              <div className={`runtime-badge ${isReady ? "ready" : ""}`}>
                <i /> {isReady ? "WASM ready" : "Connecting"}
              </div>
            </div>

            <div className="mode-tabs" role="tablist" aria-label="Input method">
              <button
                className={mode === "text" ? "selected" : ""}
                role="tab"
                aria-selected={mode === "text"}
                onClick={() => setMode("text")}
              >
                <Icon size={16}><path d="M4 6h16M4 12h16M4 18h10" stroke="currentColor" strokeLinecap="round" strokeWidth="2" /></Icon>
                Plain text
              </button>
              <button
                className={mode === "file" ? "selected" : ""}
                role="tab"
                aria-selected={mode === "file"}
                onClick={() => setMode("file")}
              >
                <Icon size={16}><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8Z" stroke="currentColor" strokeLinejoin="round" strokeWidth="2" /><path d="M14 2v6h6" stroke="currentColor" strokeLinejoin="round" strokeWidth="2" /></Icon>
                Upload .txt
              </button>
            </div>

            {mode === "text" ? (
              <div className="field">
                <div className="field-label">
                  <label htmlFor="source">Text body</label>
                  <span>{text.length.toLocaleString()} characters</span>
                </div>
                <textarea
                  id="source"
                  value={text}
                  onChange={(event) => {
                    setText(event.target.value);
                    setResults([]);
                  }}
                  spellCheck={false}
                  placeholder="Enter one constraint formula per line…"
                />
              </div>
            ) : (
              <div
                className="dropzone"
                onClick={() => fileInput.current?.click()}
                onDragOver={(event) => event.preventDefault()}
                onDrop={(event) => {
                  event.preventDefault();
                  const file = event.dataTransfer.files[0];
                  if (file) {
                    setFileName(file.name);
                    file.text().then(setText);
                  }
                }}
              >
                <input ref={fileInput} type="file" accept=".txt,text/plain" onChange={selectFile} />
                <div className="upload-icon">
                  <Icon size={22}><path d="M12 16V4m0 0L7 9m5-5 5 5M5 15v4h14v-4" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" /></Icon>
                </div>
                {fileName ? (
                  <>
                    <strong>{fileName}</strong>
                    <span>{text.length.toLocaleString()} characters loaded · Click to replace</span>
                  </>
                ) : (
                  <>
                    <strong>Drop a text file here</strong>
                    <span>or click to browse · .txt files only</span>
                  </>
                )}
              </div>
            )}

            {results.length > 0 && (
              <div className="results" aria-live="polite">
                <h3>Output</h3>
                <ol>
                  {results.map(({ lineNumber, formula, result, isError }) => (
                    <li className={isError ? "error" : ""} key={lineNumber}>
                      <details className="line-result">
                        <summary>
                          <span>Line {lineNumber}</span>
                          <code>{isError ? `Error: ${result}` : result}</code>
                          <span className="line-result-toggle" aria-hidden="true">
                            <ChevronDown className="line-result-icon line-result-icon-down" size={16} />
                            <ChevronUp className="line-result-icon line-result-icon-up" size={16} />
                          </span>
                        </summary>
                        <div className="line-formula">
                          <span>Original formula</span>
                          <code>{formula}</code>
                        </div>
                      </details>
                    </li>
                  ))}
                </ol>
              </div>
            )}

            <div className="card-footer">
              <div className="status" role="status"><i className={isReady ? "ok" : ""} />{status}</div>
              <button className="primary-button" disabled={!isReady || !text.trim()} onClick={solveInput}>
                Solve constraints
                <Icon size={16}><path d="m9 18 6-6-6-6" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" /></Icon>
              </button>
            </div>
          </div>

          <aside className="context-card">
            <span className="context-number">01</span>
            <h3>Where Blue3 fits</h3>
            <p>
              Caprice’s type checker uses concolic evaluation to generate
              logical constraints. Blue3 combines a CDCL SAT core with an
              integer-difference-logic theory solver to resolve the common,
              lightweight cases before a Z3 fallback is needed.
            </p>
            <div className="note">
              <Icon size={17}><circle cx="12" cy="12" r="9" stroke="currentColor" strokeWidth="2" /><path d="M12 11v5m0-8h.01" stroke="currentColor" strokeLinecap="round" strokeWidth="2" /></Icon>
              <span>
                Enter integer comparisons using <code>=</code>, <code>!=</code>,
                {" "}<code>&lt;</code>, <code>&lt;=</code>, <code>&gt;</code>, or
                {" "}<code>&gt;=</code>. Join them with <code>^</code> or
                {" "}<code>&amp;&amp;</code> for AND, <code>|</code> or
                {" "}<code>||</code> for OR, and <code>!</code> for NOT. Lines
                beginning with <code>#</code> are comments.
              </span>
            </div>
          </aside>
        </section>
      </main>

      <footer>
        <span>Blue3 · Caprice programming language research</span>
        <span>Powered by OCaml + WebAssembly</span>
      </footer>
    </div>
  );
}

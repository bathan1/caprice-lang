interface CapriceWasm {
  solveSmokeTest(): string;
  solveInput(input: string): string;
}

declare global {
  interface Window {
    capriceWasm?: CapriceWasm;
  }
}

let loading: Promise<CapriceWasm> | undefined;

export function loadCapriceWasm(): Promise<CapriceWasm> {
  if (window.capriceWasm) {
    return Promise.resolve(window.capriceWasm);
  }

  loading ??= new Promise((resolve, reject) => {
    const script = document.createElement("script");
    // The loader has a stable public filename, so version the URL when its
    // parser changes instead of allowing a cached runtime to survive reloads.
    script.src = `${import.meta.env.BASE_URL}caprice-wasm/main.bc.wasm.js?v=2`;
    script.onerror = () => reject(new Error("the generated loader could not be fetched"));
    document.head.appendChild(script);

    const startedAt = Date.now();
    const checkForExport = () => {
      if (window.capriceWasm) {
        resolve(window.capriceWasm);
      } else if (Date.now() - startedAt >= 10_000) {
        reject(new Error("timed out waiting for window.capriceWasm"));
      } else {
        window.setTimeout(checkForExport, 10);
      }
    };

    checkForExport();
  });

  return loading;
}

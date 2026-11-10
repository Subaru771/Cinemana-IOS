import { useCallback, useEffect, useRef, useState } from "react";
import "./App.css";
import "./cinemana.css";
import { AppleID } from "./AppleID";
import type { DeviceInfo } from "./Device";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { classify } from "./cinemana/errors";
import type { ErrorCode } from "./cinemana/errors";
import { errorText as errorStrings, ui } from "./cinemana/strings.ar-IQ";

type Stage = "signin" | "device" | "pairing" | "install" | "complete" | "error";
type OperationUpdate = {
  updateType: "started" | "finished" | "failed";
  stepId: string;
  extraDetails?: unknown;
};
const stepOrder = ["prepare", "sidestore", "pairing", "verify"];

function humanError(error: unknown): string {
  if (typeof error === "string") return error;
  if (error instanceof Error) return error.message;
  if (typeof error === "object" && error) {
    const e = error as Record<string, unknown>;
    if (typeof e.message === "string") return e.message;
    if (typeof e.Misc === "string") return e.Misc;
    try { return JSON.stringify(error); } catch {}
  }
  return ui.genericFailure;
}

function ErrorBlock({ raw, fallback }: { raw: string; fallback?: ErrorCode }) {
  const [copied, setCopied] = useState(false);
  const detected = classify(raw);
  const detail = errorStrings[detected === "UNKNOWN" && fallback ? fallback : detected];
  return <div className="cinemana-errorbox" role="alert">
    <strong>{detail.title}</strong>
    <p>{detail.body}</p>
    <p className="cinemana-fix">{detail.fix}</p>
    <details>
      <summary>{ui.actions.details}</summary>
      <pre dir="ltr">{raw}</pre>
      <button type="button" className="cinemana-secondary" onClick={() => {
        void navigator.clipboard?.writeText(raw).then(() => setCopied(true)).catch(() => {});
      }}>{copied ? ui.actions.copied : ui.actions.copyDetails}</button>
    </details>
  </div>;
}

export default function App() {
  const [loggedInAs, setLoggedInAs] = useState<string | null>(null);
  const [noKeyringAvailable, setNoKeyringAvailable] = useState(false);
  const [stage, setStage] = useState<Stage>("signin");
  const [devices, setDevices] = useState<DeviceInfo[]>([]);
  const [selectedDevice, setSelectedDevice] = useState<DeviceInfo | null>(null);
  const [loadingDevices, setLoadingDevices] = useState(false);
  const [currentStep, setCurrentStep] = useState<string>("prepare");
  const [completedSteps, setCompletedSteps] = useState<string[]>([]);
  const [errorText, setErrorText] = useState("");
  const [wasPairingError, setWasPairingError] = useState(false);
  const running = useRef(false);
  const selecting = useRef(false);

  useEffect(() => {
    invoke<boolean>("keyring_available").then((yes) => setNoKeyringAvailable(!yes)).catch(() => setNoKeyringAvailable(true));
  }, []);
  useEffect(() => {
    if (loggedInAs && stage === "signin") setStage("device");
    else if (!loggedInAs && stage === "device") setStage("signin");
  }, [loggedInAs, stage]);

  const refreshDevices = useCallback(async () => {
    setLoadingDevices(true);
    setErrorText("");
    setWasPairingError(false);
    try {
      const response = await invoke<Array<{ Ok: DeviceInfo } | { Err: unknown }>>("list_devices");
      const found = response.filter((d): d is { Ok: DeviceInfo } => "Ok" in d).map((d) => d.Ok)
        .filter((d) => d.connectionType === "USB");
      const errors = response.filter((d): d is { Err: unknown } => "Err" in d);
      setDevices(found);
      if (!found.length && errors.length) setErrorText(humanError(errors[0].Err));
    } catch (e) {
      setDevices([]);
      setErrorText(humanError(e));
    } finally { setLoadingDevices(false); }
  }, []);
  useEffect(() => {
    if (stage === "device") void refreshDevices();
  }, [stage, refreshDevices]);

  async function installBoth() {
    if (running.current) return;
    running.current = true;
    setStage("install");
    setCurrentStep("prepare");
    setCompletedSteps([]);
    setErrorText("");
    let stopListening: (() => void) | null = null;
    try {
      stopListening = await listen<OperationUpdate>("operation_cinemana_install", (event) => {
        const data = event.payload;
        if (data.updateType === "started") setCurrentStep(data.stepId);
        else if (data.updateType === "finished") {
          setCompletedSteps((previous) => previous.includes(data.stepId) ? previous : [...previous, data.stepId]);
        } else if (data.updateType === "failed") {
          setCurrentStep(data.stepId);
          setErrorText(humanError(data.extraDetails));
        }
      });
      await invoke("cinemana_install_operation");
      setStage("complete");
    } catch (e) {
      setErrorText((old) => old || humanError(e));
      setStage("error");
    } finally {
      stopListening?.();
      running.current = false;
    }
  }

  async function chooseDevice(device: DeviceInfo) {
    if (selecting.current || running.current) return;
    selecting.current = true;
    setStage("pairing");
    setWasPairingError(false);
    setErrorText("");
    try {
      await invoke("cinemana_select_device", { device });
      setSelectedDevice(device);
      selecting.current = false;
      await installBoth();
    } catch (e) {
      setWasPairingError(true);
      setErrorText(humanError(e));
      setStage("device");
      selecting.current = false;
    }
  }

  const deviceName = selectedDevice?.name;
  return <main className="cinemana-loader" dir="rtl" lang="ar">
    <div className="cinemana-shell">
      <header className="cinemana-head">
        <span className="cinemana-symbol">C</span>
        <div><h1>{ui.appName}</h1><p>{ui.tagline}</p></div>
      </header>
      <nav className="cinemana-steps" aria-label={ui.nav.label}>
        <span className={loggedInAs ? "done" : "active"}>{ui.nav.account}</span>
        <span className={stage === "device" || stage === "pairing" ? "active" : stage === "signin" ? "" : "done"}>{ui.nav.device}</span>
        <span className={stage === "install" || stage === "error" ? "active" : stage === "complete" ? "done" : ""}>{ui.nav.install}</span>
      </nav>
      {stage === "signin" && <section className="cinemana-panel">
        <h2>{ui.signIn.title}</h2>
        <p className="cinemana-muted">{ui.signIn.body}</p>
        <AppleID loggedInAs={loggedInAs} setLoggedInAs={setLoggedInAs} noKeyringAvailable={noKeyringAvailable} />
        <small className="cinemana-muted">{ui.signIn.privacy}</small>
      </section>}
      {stage === "device" && <section className="cinemana-panel">
        <h2>{ui.devices.title}</h2>
        <p className="cinemana-muted">{ui.devices.body}</p>
        <div className="cinemana-device-list">
          {devices.length === 0 && <div className="cinemana-empty">{loadingDevices ? ui.devices.loading : ui.devices.empty}</div>}
          {devices.map((device) => <button key={device.id} className="cinemana-device" onClick={() => void chooseDevice(device)}>
            <span className="cinemana-device-icon">▣</span>
            <span className="cinemana-device-text"><strong>{device.name}</strong><small dir="ltr">{device.connectionType} · iOS {device.version}</small></span>
            <span>←</span>
          </button>)}
        </div>
        {errorText && <ErrorBlock raw={errorText} fallback={wasPairingError ? "PAIRING_INVALID" : undefined} />}
        <button className="cinemana-secondary" type="button" disabled={loadingDevices} onClick={() => void refreshDevices()}>{loadingDevices ? ui.devices.checking : ui.devices.refresh}</button>
      </section>}
      {stage === "pairing" && <section className="cinemana-panel cinemana-centered">
        <div className="cinemana-spinner" aria-hidden="true" />
        <h2>{ui.trusting.title}</h2>
        <p className="cinemana-muted">{ui.trusting.body(deviceName ?? ui.trusting.fallbackName)}</p>
      </section>}
      {(stage === "install" || stage === "error") && <section className="cinemana-panel">
        <h2>{stage === "error" ? ui.progress.needsAttention : ui.progress.installingOn(deviceName ?? ui.progress.fallbackName)}</h2>
        <div className="cinemana-progress">
          {stepOrder.map((step) => <div key={step} className={`cinemana-progress-row ${completedSteps.includes(step) ? "complete" : currentStep === step ? "current" : ""}`}>
            <span className="cinemana-progress-mark">{completedSteps.includes(step) ? "✓" : currentStep === step && stage === "install" ? "◌" : "·"}</span>
            <span>{ui.steps[step]}</span>
          </div>)}
        </div>
        {stage === "error" && <>
          <ErrorBlock raw={errorText || ui.progress.notCompleted} />
          <p className="cinemana-muted">{ui.progress.retryNote}</p>
          <div className="cinemana-buttons"><button onClick={() => void installBoth()}>{ui.actions.retry}</button><button className="cinemana-secondary" onClick={() => { setSelectedDevice(null); setStage("device"); }}>{ui.actions.otherDevice}</button></div>
        </>}
        {stage === "install" && <p className="cinemana-muted">{ui.progress.keepUnlocked}</p>}
      </section>}
      {stage === "complete" && <section className="cinemana-panel">
        <div className="cinemana-done">✓</div>
        <h2>{ui.success.title}</h2>
        <p className="cinemana-muted">{ui.success.body}</p>
        <h3>{ui.success.finishTitle}</h3>
        <p>{ui.success.trust}</p>
        <p>{ui.success.vpn}</p>
        <p className="cinemana-muted">{ui.success.note80045}</p>
        <button className="cinemana-secondary" onClick={() => { setSelectedDevice(null); setStage("device"); }}>{ui.success.another}</button>
      </section>}
      <footer className="cinemana-footer">{ui.footer}</footer>
    </div>
  </main>;
}
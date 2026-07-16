import {
  createUniver,
  IUniverInstanceService,
  LifecycleStages,
  LocaleType,
} from "@univerjs/presets";
import {
  ILayoutService,
  UniverSheetsCorePreset,
} from "@univerjs/preset-sheets-core";
import esES from "@univerjs/preset-sheets-core/locales/es-ES";
import "@univerjs/preset-sheets-core/lib/index.css";

const CHANGE_DEBOUNCE_MS = 180;
const EVENT_READY = "vinabike-univer-ready";
const EVENT_CHANGED = "vinabike-univer-changed";
const EVENT_ERROR = "vinabike-univer-error";

const instances = new Map();

function dispatchBridgeEvent(name, detail) {
  window.dispatchEvent(new CustomEvent(name, { detail }));
}

function errorMessage(error) {
  if (error instanceof Error && error.message) return error.message;
  if (typeof error === "string") return error;

  try {
    return JSON.stringify(error);
  } catch (_) {
    return String(error);
  }
}

function dispatchError(viewId, error) {
  dispatchBridgeEvent(EVENT_ERROR, {
    viewId,
    message: errorMessage(error),
  });
}

function assertViewId(viewId) {
  if (typeof viewId !== "string" || viewId.trim() === "") {
    throw new TypeError("viewId must be a non-empty string.");
  }

  return viewId;
}

function assertContainer(containerElement) {
  if (!(containerElement instanceof HTMLElement)) {
    throw new TypeError("containerElement must be an HTMLElement.");
  }

  return containerElement;
}

function parseSnapshot(viewId, snapshotJson) {
  if (typeof snapshotJson !== "string") {
    throw new TypeError("snapshotJson must be a JSON string.");
  }

  const parsed = snapshotJson.trim() === "" ? {} : JSON.parse(snapshotJson);
  if (parsed === null || Array.isArray(parsed) || typeof parsed !== "object") {
    throw new TypeError("snapshotJson must contain a JSON object.");
  }

  const snapshot = { ...parsed };
  if (typeof snapshot.id !== "string" || snapshot.id === "") {
    snapshot.id = `vinabike-workbook-${viewId}`;
  }
  if (typeof snapshot.name !== "string") {
    snapshot.name = "Spreadsheet";
  }
  if (typeof snapshot.locale !== "string") {
    snapshot.locale = LocaleType.ES_ES;
  }

  const sheets =
    snapshot.sheets &&
    !Array.isArray(snapshot.sheets) &&
    typeof snapshot.sheets === "object"
      ? { ...snapshot.sheets }
      : {};
  let sheetOrder = Array.isArray(snapshot.sheetOrder)
    ? [...snapshot.sheetOrder]
    : Object.keys(sheets);

  if (sheetOrder.length === 0) {
    const sheetId = `${snapshot.id}-sheet-1`;
    sheets[sheetId] = {
      id: sheetId,
      name: "Sheet 1",
      rowCount: 1000,
      columnCount: 26,
      cellData: {},
    };
    sheetOrder = [sheetId];
  }

  snapshot.sheets = sheets;
  snapshot.sheetOrder = sheetOrder;
  return snapshot;
}

function getInstance(viewId) {
  const normalizedViewId = assertViewId(viewId);
  const instance = instances.get(normalizedViewId);
  if (!instance || instance.disposed) {
    throw new Error(
      `No Univer spreadsheet is mounted for view ${normalizedViewId}.`,
    );
  }

  return instance;
}

function serializeSnapshot(instance) {
  return JSON.stringify(instance.workbook.save());
}

function serializeExplicitSnapshot(instance) {
  if (instance.changeTimer !== null) {
    window.clearTimeout(instance.changeTimer);
    instance.changeTimer = null;
  }

  const snapshotJson = serializeSnapshot(instance);
  // The caller will persist this exact snapshot. A command raised while
  // committing an active editor must not dispatch the same workbook again and
  // make Flutter immediately consider the just-saved workbook dirty.
  instance.lastDispatchedSnapshotJson = snapshotJson;
  return snapshotJson;
}

function flushChanged(instance) {
  instance.changeTimer = null;
  if (instance.disposed) return;

  try {
    const snapshotJson = serializeSnapshot(instance);
    if (snapshotJson === instance.lastDispatchedSnapshotJson) return;

    instance.lastDispatchedSnapshotJson = snapshotJson;
    dispatchBridgeEvent(EVENT_CHANGED, {
      viewId: instance.viewId,
      snapshotJson,
    });
  } catch (error) {
    dispatchError(instance.viewId, error);
  }
}

function scheduleChanged(instance) {
  if (instance.disposed) return;
  if (instance.changeTimer !== null) {
    window.clearTimeout(instance.changeTimer);
  }

  instance.changeTimer = window.setTimeout(
    () => flushChanged(instance),
    CHANGE_DEBOUNCE_MS,
  );
}

function isDocCommand(commandId) {
  return typeof commandId === "string" && /^docs?(?:[.\-]|$)/.test(commandId);
}

function disposeInstance(instance) {
  if (!instance || instance.disposed) return;
  instance.disposed = true;
  instances.delete(instance.viewId);

  if (instance.changeTimer !== null) {
    window.clearTimeout(instance.changeTimer);
    instance.changeTimer = null;
  }

  for (const disposable of instance.disposables.splice(0)) {
    try {
      disposable.dispose();
    } catch (_) {
      // Continue disposing the remaining Univer resources.
    }
  }

  try {
    instance.univerAPI.disposeUnit(instance.workbookId);
  } catch (_) {
    // The unit may already have been disposed by Univer.
  }

  try {
    instance.univerAPI.dispose();
  } catch (_) {
    // Continue with the root Univer disposal.
  }

  try {
    instance.univer.dispose();
  } finally {
    instance.containerElement.replaceChildren();
  }
}

function mount(viewId, containerElement, snapshotJson) {
  const normalizedViewId =
    typeof viewId === "string" ? viewId : String(viewId ?? "");
  let partialInstance = null;

  try {
    assertViewId(normalizedViewId);
    const container = assertContainer(containerElement);
    const snapshotData = parseSnapshot(normalizedViewId, snapshotJson);

    const existingForView = instances.get(normalizedViewId);
    if (existingForView) disposeInstance(existingForView);

    for (const instance of instances.values()) {
      if (instance.containerElement === container) disposeInstance(instance);
    }

    container.replaceChildren();

    const { univer, univerAPI } = createUniver({
      locale: LocaleType.ES_ES,
      locales: {
        [LocaleType.ES_ES]: esES,
      },
      presets: [
        UniverSheetsCorePreset({
          container,
          header: true,
          toolbar: true,
          ribbonType: "classic",
          formulaBar: true,
          footer: {
            sheetBar: true,
            statisticBar: true,
            menus: true,
            zoomSlider: true,
            addSheetButtonConfig: {
              show: true,
              defaultRowCount: 1000,
              defaultColumnCount: 26,
            },
          },
          contextMenu: true,
        }),
      ],
    });

    partialInstance = {
      viewId: normalizedViewId,
      containerElement: container,
      univer,
      univerAPI,
      workbook: null,
      workbookId: "",
      disposables: [],
      changeTimer: null,
      disposed: false,
      readySent: false,
      lastDispatchedSnapshotJson: "",
    };

    const readyDisposable = univerAPI.addEvent(
      univerAPI.Event.LifeCycleChanged,
      ({ stage }) => {
        if (
          !partialInstance.disposed &&
          !partialInstance.readySent &&
          stage >= LifecycleStages.Rendered
        ) {
          partialInstance.readySent = true;
          dispatchBridgeEvent(EVENT_READY, { viewId: normalizedViewId });
        }
      },
    );
    partialInstance.disposables.push(readyDisposable);

    const valueDisposable = univerAPI.addEvent(
      univerAPI.Event.SheetValueChanged,
      () => scheduleChanged(partialInstance),
    );
    partialInstance.disposables.push(valueDisposable);

    const commandDisposable = univerAPI.addEvent(
      univerAPI.Event.CommandExecuted,
      ({ id }) => {
        if (!isDocCommand(id)) scheduleChanged(partialInstance);
      },
    );
    partialInstance.disposables.push(commandDisposable);

    const workbook = univerAPI.createWorkbook(snapshotData);
    partialInstance.workbook = workbook;
    partialInstance.workbookId = workbook.getId();
    partialInstance.lastDispatchedSnapshotJson =
      serializeSnapshot(partialInstance);
    instances.set(normalizedViewId, partialInstance);

    if (univerAPI.getCurrentLifecycleStage() >= LifecycleStages.Rendered) {
      queueMicrotask(() => {
        if (!partialInstance.disposed && !partialInstance.readySent) {
          partialInstance.readySent = true;
          dispatchBridgeEvent(EVENT_READY, { viewId: normalizedViewId });
        }
      });
    }
  } catch (error) {
    if (partialInstance) disposeInstance(partialInstance);
    dispatchError(normalizedViewId, error);
    throw error;
  }
}

function snapshot(viewId) {
  const normalizedViewId =
    typeof viewId === "string" ? viewId : String(viewId ?? "");

  try {
    const instance = getInstance(normalizedViewId);
    if (!instance.workbook.isCellEditing()) {
      return serializeExplicitSnapshot(instance);
    }

    return instance.workbook
      .endEditingAsync(true)
      .then((committed) => {
        if (!committed) {
          throw new Error("Univer could not commit the active cell edit.");
        }
        return serializeExplicitSnapshot(instance);
      })
      .catch((error) => {
        dispatchError(normalizedViewId, error);
        throw error;
      });
  } catch (error) {
    dispatchError(normalizedViewId, error);
    throw error;
  }
}

function dispose(viewId) {
  const normalizedViewId =
    typeof viewId === "string" ? viewId : String(viewId ?? "");
  const instance = instances.get(normalizedViewId);
  if (instance) disposeInstance(instance);
}

function focus(viewId) {
  const normalizedViewId =
    typeof viewId === "string" ? viewId : String(viewId ?? "");

  try {
    const instance = getInstance(normalizedViewId);
    const injector = instance.univer.__getInjector();
    injector.get(IUniverInstanceService).focusUnit(instance.workbookId);
    instance.univerAPI.setCurrent(instance.workbookId);
    if (!instance.containerElement.hasAttribute("tabindex")) {
      instance.containerElement.setAttribute("tabindex", "-1");
    }
    instance.containerElement.focus({ preventScroll: true });
    injector.get(ILayoutService).focus();
  } catch (error) {
    dispatchError(normalizedViewId, error);
    throw error;
  }
}

globalThis.vinabikeUniver = Object.freeze({
  mount,
  snapshot,
  dispose,
  focus,
});

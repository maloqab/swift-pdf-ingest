const state = {
  currentDocument: null,
};

const elements = {
  form: document.getElementById("upload-form"),
  fileInput: document.getElementById("file-input"),
  fileName: document.getElementById("file-name"),
  submitButton: document.getElementById("submit-button"),
  statusPill: document.getElementById("status-pill"),
  resultShell: document.getElementById("result-shell"),
  resultStatus: document.getElementById("result-status"),
  metricsGrid: document.getElementById("metrics-grid"),
  resultMeta: document.getElementById("result-meta"),
  cleanText: document.getElementById("clean-text"),
  jsonOutput: document.getElementById("json-output"),
  pagesList: document.getElementById("pages-list"),
  pageCountLabel: document.getElementById("page-count-label"),
  recentList: document.getElementById("recent-list"),
  refreshButton: document.getElementById("refresh-button"),
  copyTextButton: document.getElementById("copy-text-button"),
  copyJSONButton: document.getElementById("copy-json-button"),
};

function setStatus(label, kind = "idle") {
  elements.statusPill.textContent = label;
  elements.statusPill.className = `status-pill ${kind}`;
}

function setResultStatus(label, kind = "idle") {
  elements.resultStatus.textContent = label;
  elements.resultStatus.className = `status-pill ${kind}`;
}

function escapeHTML(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function renderMetrics(documentPayload, responsePayload) {
  const metrics = [
    ["Pages", String(documentPayload.pageCount)],
    ["Warnings", String(documentPayload.warningPageCount)],
    ["Avg. quality", documentPayload.averageQualityScore.toFixed(3)],
    ["Cache hit", responsePayload.wasCached ? "Yes" : "No"],
  ];

  elements.metricsGrid.innerHTML = metrics
    .map(
      ([label, value]) => `
        <div class="metric">
          <span class="metric-label">${label}</span>
          <span class="metric-value">${value}</span>
        </div>
      `
    )
    .join("");
}

function renderMeta(documentPayload, responsePayload) {
  const metaRows = [
    ["Title", documentPayload.title],
    ["Filename", documentPayload.filename],
    ["SHA-256", documentPayload.sha256],
    ["Updated", documentPayload.updatedAt || "Unknown"],
    ["Source label", documentPayload.sourceLabel || "None"],
    ["Source URL", documentPayload.sourceURL || "None"],
    ["Source unit", documentPayload.sourceUnit || "None"],
    ["Status", responsePayload.ingestStatus],
  ];

  if (responsePayload.ingestError) {
    metaRows.push(["Error", responsePayload.ingestError]);
  }

  elements.resultMeta.innerHTML = metaRows
    .map(
      ([label, value]) => `
        <div class="meta-card">
          <h3>${label}</h3>
          <p>${escapeHTML(String(value))}</p>
        </div>
      `
    )
    .join("");
}

function renderPages(documentPayload) {
  elements.pageCountLabel.textContent = `${documentPayload.pageCount} page${documentPayload.pageCount === 1 ? "" : "s"}`;

  elements.pagesList.innerHTML = documentPayload.pages
    .map((page) => {
      const caption = `${page.extractionMethod} • q=${page.qualityScore.toFixed(3)} • dpi=${page.dpi} • ${page.numericSanityStatus}`;
      const normalized = page.normalizedTextContent || page.textContent;
      return `
        <details class="page-card">
          <summary>
            <h3>Page ${page.pageNumber}</h3>
            <span class="panel-caption">${escapeHTML(caption)}</span>
          </summary>
          <pre>${escapeHTML(normalized)}</pre>
        </details>
      `;
    })
    .join("");
}

function renderDocument(responsePayload) {
  state.currentDocument = responsePayload;
  const { document: documentPayload, ingestStatus } = responsePayload;

  elements.resultShell.classList.remove("hidden");
  setResultStatus(ingestStatus, ingestStatus === "failed" ? "failed" : "processed");
  renderMetrics(documentPayload, responsePayload);
  renderMeta(documentPayload, responsePayload);
  elements.cleanText.textContent = documentPayload.cleanText || documentPayload.rawText || "";
  elements.jsonOutput.textContent = JSON.stringify(responsePayload, null, 2);
  renderPages(documentPayload);
}

async function refreshDocuments() {
  elements.recentList.innerHTML = `<div class="empty-state">Loading recent documents…</div>`;
  try {
    const response = await fetch("/api/documents?limit=12");
    if (!response.ok) {
      throw new Error("Failed to load documents.");
    }
    const documents = await response.json();
    if (!documents.length) {
      elements.recentList.innerHTML = `<div class="empty-state">No documents ingested yet.</div>`;
      return;
    }

    elements.recentList.innerHTML = documents
      .map(
        (document) => `
          <button class="recent-card" type="button" data-document-id="${document.id}">
            <h3>${escapeHTML(document.title)}</h3>
            <p>${escapeHTML(document.filename)}</p>
            <p>${document.pageCount} pages • ${document.warningPageCount} warnings • q=${document.averageQualityScore.toFixed(3)}</p>
          </button>
        `
      )
      .join("");
  } catch (error) {
    elements.recentList.innerHTML = `<div class="empty-state">${escapeHTML(error.message)}</div>`;
  }
}

async function loadDocument(documentID) {
  const response = await fetch(`/api/documents/${documentID}`);
  if (!response.ok) {
    throw new Error("Failed to load document.");
  }
  const documentPayload = await response.json();
  renderDocument({
    ingestStatus: "stored",
    ingestError: null,
    wasCached: true,
    document: documentPayload,
  });
}

elements.fileInput.addEventListener("change", () => {
  const file = elements.fileInput.files?.[0];
  elements.fileName.textContent = file ? file.name : "or choose a file";
});

elements.form.addEventListener("submit", async (event) => {
  event.preventDefault();
  const file = elements.fileInput.files?.[0];
  if (!file) {
    setStatus("Pick a PDF", "failed");
    return;
  }

  const formData = new FormData(elements.form);
  setStatus("Processing", "processing");
  elements.submitButton.disabled = true;

  try {
    const response = await fetch("/api/upload", {
      method: "POST",
      body: formData,
    });

    const payload = await response.json();
    if (!response.ok) {
      throw new Error(payload.reason || payload.error || "Upload failed.");
    }

    renderDocument(payload);
    setStatus(payload.ingestStatus === "failed" ? "Needs review" : "Ready", payload.ingestStatus);
    await refreshDocuments();
  } catch (error) {
    setStatus("Failed", "failed");
    alert(error.message);
  } finally {
    elements.submitButton.disabled = false;
  }
});

elements.refreshButton.addEventListener("click", refreshDocuments);

elements.recentList.addEventListener("click", async (event) => {
  const card = event.target.closest("[data-document-id]");
  if (!card) {
    return;
  }

  try {
    await loadDocument(card.dataset.documentId);
  } catch (error) {
    alert(error.message);
  }
});

elements.copyTextButton.addEventListener("click", async () => {
  await navigator.clipboard.writeText(elements.cleanText.textContent || "");
});

elements.copyJSONButton.addEventListener("click", async () => {
  await navigator.clipboard.writeText(elements.jsonOutput.textContent || "");
});

refreshDocuments();
